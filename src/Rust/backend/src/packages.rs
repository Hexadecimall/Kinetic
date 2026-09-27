//! Verified, opt-in package operations for the bundled command-line client.

use serde_json::{Value, json};
use std::env;
use std::fs::{self, File};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

const catalogUrl: &str = "https://hexadecimall.github.io/Kinetic/plugins/index.json";
const releasesUrl: &str = "https://api.github.com/repos/Hexadecimall/Kinetic/releases?per_page=30";
const maxPluginBytes: u64 = 32 * 1024 * 1024;
const maxAppBytes: u64 = 512 * 1024 * 1024;

fn failure(message: impl AsRef<str>) -> i32 {
    eprintln!("kinetic: {}", message.as_ref());
    1
}

fn homePath() -> Result<PathBuf, String> {
    env::var_os("HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .ok_or_else(|| "HOME is not set".to_string())
}

fn pluginRoot() -> Result<PathBuf, String> {
    Ok(homePath()?.join(".kinetic/plugins"))
}

fn appRoot() -> Result<PathBuf, String> {
    Ok(homePath()?.join("Applications/Kinetic.app"))
}

fn safeId(id: &str) -> bool {
    id.len() <= 128
        && id.split('.').count() >= 2
        && id.split('.').all(|part| {
            !part.is_empty()
                && part.len() <= 64
                && part
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-')
        })
}

fn string<'a>(value: &'a Value, field: &str) -> Result<&'a str, String> {
    value[field]
        .as_str()
        .ok_or_else(|| format!("missing {field} in package metadata"))
}

fn versionParts(version: &str) -> Option<[u32; 3]> {
    let mut parts = version.split('.').map(str::parse::<u32>);
    let value = [
        parts.next()?.ok()?,
        parts.next()?.ok()?,
        parts.next()?.ok()?,
    ];
    parts.next().is_none().then_some(value)
}

fn sha256(path: &Path) -> Result<String, String> {
    let output = Command::new("/usr/bin/shasum")
        .args(["-a", "256"])
        .arg(path)
        .output()
        .map_err(|error| format!("cannot hash download: {error}"))?;
    if !output.status.success() {
        return Err("cannot hash download".into());
    }
    let text = String::from_utf8(output.stdout).map_err(|_| "invalid hash output")?;
    let hash = text.split_whitespace().next().ok_or("empty hash output")?;
    if hash.len() != 64 || !hash.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err("invalid SHA-256 output".into());
    }
    Ok(hash.to_ascii_lowercase())
}

fn checkDigest(path: &Path, expected: &str, maximum: u64) -> Result<(), String> {
    if expected.len() != 64 || !expected.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err("release does not provide a valid SHA-256 digest".into());
    }
    let length = fs::metadata(path)
        .map_err(|error| format!("cannot inspect download: {error}"))?
        .len();
    if length == 0 || length > maximum {
        return Err("download size is outside the allowed range".into());
    }
    if sha256(path)? != expected.to_ascii_lowercase() {
        return Err("download SHA-256 does not match the published digest".into());
    }
    Ok(())
}

fn download(url: &str, target: &Path, maximum: u64) -> Result<(), String> {
    if !url.starts_with("https://") || url.contains(['\n', '\r']) {
        return Err("package URL must use HTTPS".into());
    }
    let result = Command::new("/usr/bin/curl")
        .args([
            "--fail",
            "--location",
            "--silent",
            "--show-error",
            "--proto",
            "=https",
            "--proto-redir",
            "=https",
            "--connect-timeout",
            "15",
            "--max-time",
            "120",
            "--max-filesize",
            &maximum.to_string(),
            "--user-agent",
            "Kinetic-Package-Client",
            "--output",
        ])
        .arg(target)
        .arg(url)
        .status()
        .map_err(|error| format!("cannot start download: {error}"))?;
    if !result.success() {
        return Err("download failed".into());
    }
    let length = fs::metadata(target)
        .map_err(|error| format!("download is missing: {error}"))?
        .len();
    if length == 0 || length > maximum {
        return Err("download size is outside the allowed range".into());
    }
    Ok(())
}

fn fetchJson(url: &str, maximum: u64) -> Result<Value, String> {
    let temporary = TemporaryFile::new("catalog")?;
    download(url, &temporary.path, maximum)?;
    let bytes = fs::read(&temporary.path).map_err(|error| error.to_string())?;
    serde_json::from_slice(&bytes).map_err(|error| format!("invalid catalog JSON: {error}"))
}

struct TemporaryFile {
    path: PathBuf,
}

impl TemporaryFile {
    fn new(label: &str) -> Result<Self, String> {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|error| error.to_string())?
            .as_nanos();
        let path = env::temp_dir().join(format!("kinetic-{label}-{}-{stamp}", std::process::id()));
        File::create_new(&path).map_err(|error| format!("cannot create staging file: {error}"))?;
        Ok(Self { path })
    }
}

impl Drop for TemporaryFile {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

fn catalog() -> Result<Value, String> {
    let catalog = fetchJson(catalogUrl, 4 * 1024 * 1024)?;
    if catalog["schemaVersion"] != 1 || !catalog["plugins"].is_array() {
        return Err("unsupported plugin catalog".into());
    }
    Ok(catalog)
}

fn catalogPlugin<'a>(catalog: &'a Value, id: &str) -> Result<&'a Value, String> {
    catalog["plugins"]
        .as_array()
        .and_then(|plugins| plugins.iter().find(|plugin| plugin["id"] == id))
        .ok_or_else(|| format!("plugin {id} was not found in the public catalog"))
}

fn latestPluginRelease(plugin: &Value) -> Result<&Value, String> {
    plugin["releases"]
        .as_array()
        .and_then(|releases| {
            releases
                .iter()
                .filter(|release| {
                    release["platform"] == "macos-arm64" && release["apiVersion"] == 1
                })
                .filter_map(|release| Some((versionParts(release["version"].as_str()?)?, release)))
                .max_by_key(|(version, _)| *version)
                .map(|(_, release)| release)
        })
        .ok_or_else(|| "plugin has no compatible macOS arm64 release".to_string())
}

fn managedRecord(id: &str) -> Result<PathBuf, String> {
    if !safeId(id) {
        return Err("invalid plugin ID".into());
    }
    Ok(pluginRoot()?.join(".managed").join(format!("{id}.json")))
}

fn installedRecord(id: &str) -> Result<Option<Value>, String> {
    let path = managedRecord(id)?;
    if !path.exists() {
        return Ok(None);
    }
    let bytes =
        fs::read(&path).map_err(|error| format!("cannot read installed metadata: {error}"))?;
    let record: Value = serde_json::from_slice(&bytes)
        .map_err(|error| format!("installed metadata is invalid: {error}"))?;
    if record["id"] != id || record["file"] != format!("{id}.dylib") {
        return Err("installed metadata does not match its plugin ID".into());
    }
    Ok(Some(record))
}

fn writeRecord(id: &str, record: &Value) -> Result<(), String> {
    let path = managedRecord(id)?;
    let parent = path.parent().ok_or("invalid managed plugin path")?;
    fs::create_dir_all(parent)
        .map_err(|error| format!("cannot create plugin metadata: {error}"))?;
    let temporary = parent.join(format!(".{id}.{}.tmp", std::process::id()));
    let mut file = File::create_new(&temporary)
        .map_err(|error| format!("cannot stage plugin metadata: {error}"))?;
    let result = (|| {
        serde_json::to_writer_pretty(&mut file, record).map_err(|error| error.to_string())?;
        file.write_all(b"\n").map_err(|error| error.to_string())?;
        file.sync_all().map_err(|error| error.to_string())?;
        fs::rename(&temporary, &path).map_err(|error| error.to_string())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

fn isMachOArm64(path: &Path) -> Result<bool, String> {
    let mut bytes = [0u8; 16];
    File::open(path)
        .and_then(|mut file| file.read_exact(&mut bytes))
        .map_err(|error| format!("cannot read plugin header: {error}"))?;
    let magic = u32::from_le_bytes(bytes[..4].try_into().map_err(|_| "short Mach-O header")?);
    let cpu = u32::from_le_bytes(bytes[4..8].try_into().map_err(|_| "short Mach-O header")?);
    let fileType = u32::from_le_bytes(
        bytes[12..16]
            .try_into()
            .map_err(|_| "short Mach-O header")?,
    );
    Ok(magic == 0xfeed_facf && cpu == 0x0100_000c && matches!(fileType, 6 | 8))
}

fn confirm(description: &str) -> Result<bool, String> {
    if env::args().any(|arg| arg == "--yes") {
        return Ok(true);
    }
    print!("{description} [y/N] ");
    io::stdout().flush().map_err(|error| error.to_string())?;
    let mut reply = String::new();
    io::stdin()
        .read_line(&mut reply)
        .map_err(|error| error.to_string())?;
    Ok(reply.trim().eq_ignore_ascii_case("y") || reply.trim().eq_ignore_ascii_case("yes"))
}

fn pluginList(jsonOutput: bool) -> Result<(), String> {
    let catalog = catalog()?;
    let mut display = Vec::new();
    for plugin in catalog["plugins"].as_array().ok_or("invalid catalog")? {
        let id = string(plugin, "id")?;
        if !safeId(id) {
            continue;
        }
        let release = latestPluginRelease(plugin)?;
        let installed = installedRecord(id)?;
        let state = if let Some(record) = installed {
            let version = record["version"].as_str().unwrap_or("unknown");
            if versionParts(version) < versionParts(string(release, "version")?) {
                format!("update available ({version})")
            } else {
                format!("installed ({version})")
            }
        } else {
            "available".to_string()
        };
        if jsonOutput {
            display.push(json!({
                "id": id,
                "name": string(plugin, "name")?,
                "summary": string(plugin, "summary")?,
                "version": string(release, "version")?,
                "publisher": string(&plugin["publisher"], "githubLogin")?,
                "publisherId": plugin["publisher"]["githubId"],
                "official": plugin["official"] == true,
                "platform": release["platform"],
                "apiVersion": release["apiVersion"],
                "sizeBytes": release["asset"]["sizeBytes"],
                "state": state,
            }));
        } else {
            println!("{id}\t{}\t{state}", string(plugin, "name")?);
        }
    }
    if jsonOutput {
        println!(
            "{}",
            serde_json::to_string(&display).map_err(|error| error.to_string())?
        );
    }
    Ok(())
}

#[allow(
    clippy::too_many_lines,
    reason = "the install transaction keeps rollback steps together"
)]
fn pluginInstall(id: &str, updateOnly: bool) -> Result<(), String> {
    if !safeId(id) {
        return Err("invalid plugin ID".into());
    }
    let catalog = catalog()?;
    let plugin = catalogPlugin(&catalog, id)?;
    let release = latestPluginRelease(plugin)?;
    let version = string(release, "version")?;
    let publisher = string(&plugin["publisher"], "githubLogin")?;
    let publisherId = plugin["publisher"]["githubId"]
        .as_u64()
        .ok_or("missing publisher ID")?;
    if plugin["official"] == true && publisherId != 121_444_149 {
        return Err("Official publisher identity does not match Kinetic".into());
    }
    let prior = installedRecord(id)?;
    if updateOnly && prior.is_none() {
        return Err("plugin is not installed".into());
    }
    if let Some(record) = &prior {
        if record["publisherId"] != publisherId {
            return Err("publisher identity changed; update refused".into());
        }
        if versionParts(record["version"].as_str().unwrap_or("")) >= versionParts(version) {
            println!("{id} is already current ({version}).");
            return Ok(());
        }
    }
    let asset = &release["asset"];
    let url = string(asset, "url")?;
    if !url.starts_with(&format!("https://github.com/{publisher}/"))
        || !url.contains("/releases/download/")
        || !Path::new(url)
            .extension()
            .is_some_and(|extension| extension.eq_ignore_ascii_case("dylib"))
    {
        return Err("plugin asset is not a release download owned by its publisher".into());
    }
    let expected = string(asset, "sha256")?;
    let expectedBytes = asset["sizeBytes"].as_u64().ok_or("missing plugin size")?;
    if expectedBytes == 0 || expectedBytes > maxPluginBytes {
        return Err("plugin size is outside the allowed range".into());
    }
    let trust = if plugin["official"] == true {
        "Official"
    } else {
        "Community"
    };
    if !confirm(&format!(
        "{} {} {version} by {publisher} ({trust}, GitHub ID {publisherId}) runs native code with your permissions. {}?",
        if prior.is_some() { "Update" } else { "Install" },
        string(plugin, "name")?,
        if prior.is_some() { "Update" } else { "Install" }
    ))? {
        return Err("cancelled".into());
    }
    let root = pluginRoot()?;
    fs::create_dir_all(&root)
        .map_err(|error| format!("cannot create plugin directory: {error}"))?;
    let target = root.join(format!("{id}.dylib"));
    if target.symlink_metadata().is_ok() && prior.is_none() {
        return Err("an unmanaged file already occupies this plugin path".into());
    }
    if target
        .symlink_metadata()
        .is_ok_and(|meta| !meta.file_type().is_file())
    {
        return Err("plugin target is not a regular file".into());
    }
    let staged = root.join(format!(".{id}.{}.download", std::process::id()));
    let result = (|| {
        if staged.symlink_metadata().is_ok() {
            return Err("plugin staging path already exists".into());
        }
        download(url, &staged, maxPluginBytes)?;
        if fs::metadata(&staged)
            .map_err(|error| error.to_string())?
            .len()
            != expectedBytes
        {
            return Err("plugin download size does not match the catalog".into());
        }
        checkDigest(&staged, expected, maxPluginBytes)?;
        if !isMachOArm64(&staged)? {
            return Err("plugin is not an arm64 Mach-O dynamic library".into());
        }
        let record = json!({
            "id": id, "version": version, "file": format!("{id}.dylib"),
            "sha256": expected, "publisherId": publisherId, "publisher": publisher,
            "official": plugin["official"] == true,
        });
        let backup = root.join(format!(".{id}.{}.previous", std::process::id()));
        let hadPrior = prior.is_some();
        if hadPrior {
            fs::rename(&target, &backup)
                .map_err(|error| format!("cannot stage previous plugin: {error}"))?;
        }
        if let Err(error) = fs::rename(&staged, &target) {
            if hadPrior {
                let _ = fs::rename(&backup, &target);
            }
            return Err(format!("cannot install plugin: {error}"));
        }
        if let Err(error) = writeRecord(id, &record) {
            let _ = fs::remove_file(&target);
            if hadPrior {
                let _ = fs::rename(&backup, &target);
            }
            return Err(error);
        }
        if hadPrior {
            let _ = fs::remove_file(&backup);
        }
        Ok(())
    })();
    let _ = fs::remove_file(&staged);
    result?;
    println!("{id} {version} installed. Restart Kinetic to load it.");
    Ok(())
}

fn pluginUninstall(id: &str) -> Result<(), String> {
    let record = installedRecord(id)?.ok_or("plugin is not managed by Kinetic")?;
    let target = pluginRoot()?.join(string(&record, "file")?);
    if !target
        .symlink_metadata()
        .is_ok_and(|meta| meta.file_type().is_file())
    {
        return Err("installed plugin file is missing or not a regular file".into());
    }
    if !confirm(&format!(
        "Remove {id}? The plugin file will be kept for recovery"
    ))? {
        return Err("cancelled".into());
    }
    let trash = pluginRoot()?.join(".removed");
    fs::create_dir_all(&trash).map_err(|error| error.to_string())?;
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?
        .as_secs();
    let destination = trash.join(format!("{id}-{stamp}.dylib"));
    if destination.exists() {
        return Err("recovery path already exists".into());
    }
    fs::rename(&target, &destination).map_err(|error| format!("cannot remove plugin: {error}"))?;
    if let Err(error) = fs::remove_file(managedRecord(id)?) {
        let _ = fs::rename(&destination, &target);
        return Err(format!("cannot remove plugin metadata: {error}"));
    }
    println!(
        "Removed {id}. Recovery copy: {}. Restart Kinetic.",
        destination.display()
    );
    Ok(())
}

fn appRelease() -> Result<Option<(String, String, String, u64)>, String> {
    let releases = fetchJson(releasesUrl, 4 * 1024 * 1024)?;
    let list = releases
        .as_array()
        .ok_or("invalid GitHub releases response")?;
    let mut selected: Option<(String, String, String, u64)> = None;
    for release in list {
        let Some(version) = release["tag_name"]
            .as_str()
            .and_then(|tag| tag.strip_prefix('v'))
        else {
            continue;
        };
        if versionParts(version).is_none()
            || release["draft"] == true
            || release["prerelease"] == true
            || release["immutable"] != true
        {
            continue;
        }
        let name = format!("Kinetic-{version}-macos-arm64.zip");
        let Some(asset) = release["assets"]
            .as_array()
            .and_then(|assets| assets.iter().find(|asset| asset["name"] == name))
        else {
            continue;
        };
        let digest = string(asset, "digest")?
            .strip_prefix("sha256:")
            .ok_or("release asset has no SHA-256 digest")?;
        let url = string(asset, "browser_download_url")?;
        if !url.starts_with(&format!(
            "https://github.com/Hexadecimall/Kinetic/releases/download/v{version}/"
        )) || !url.ends_with(&name)
        {
            return Err("unexpected application release URL".into());
        }
        let size = asset["size"].as_u64().ok_or("release asset has no size")?;
        if size == 0 || size > maxAppBytes {
            return Err("application release size is outside the allowed range".into());
        }
        let candidate = (
            version.to_string(),
            url.to_string(),
            digest.to_string(),
            size,
        );
        if selected
            .as_ref()
            .is_none_or(|current| versionParts(&candidate.0) > versionParts(&current.0))
        {
            selected = Some(candidate);
        }
    }
    Ok(selected)
}

fn bundleField(bundle: &Path, field: &str) -> Result<String, String> {
    let output = Command::new("/usr/libexec/PlistBuddy")
        .args(["-c", &format!("Print :{field}")])
        .arg(bundle.join("Contents/Info.plist"))
        .output()
        .map_err(|error| format!("cannot read app metadata: {error}"))?;
    if !output.status.success() {
        return Err(format!("app metadata is missing {field}"));
    }
    String::from_utf8(output.stdout)
        .map(|value| value.trim().to_string())
        .map_err(|_| "app metadata is not UTF-8".into())
}

fn verifyKineticBundle(bundle: &Path) -> Result<(), String> {
    if bundleField(bundle, "CFBundleIdentifier")? != "top.frameworksdev.kinetic" {
        return Err("application target is not a Kinetic bundle".into());
    }
    Ok(())
}

fn appCheck() -> Result<(), String> {
    if let Some((version, _, _, _)) = appRelease()? {
        let current = installedAppVersion()?;
        if versionParts(&version) > versionParts(&current) {
            println!("Kinetic {version} is available (current {current}).");
        } else {
            println!("Kinetic {current} is current.");
        }
    } else {
        println!("No application release is published yet.");
    }
    Ok(())
}

fn installedAppVersion() -> Result<String, String> {
    let target = appRoot()?;
    if target.symlink_metadata().is_ok() {
        verifyKineticBundle(&target)?;
        bundleField(&target, "CFBundleShortVersionString")
    } else {
        Ok(env!("CARGO_PKG_VERSION").to_string())
    }
}

#[allow(
    clippy::too_many_lines,
    reason = "the app replacement transaction keeps recovery steps together"
)]
fn appInstall(updateOnly: bool) -> Result<(), String> {
    let (version, url, digest, size) =
        appRelease()?.ok_or("no application release is published yet")?;
    let target = appRoot()?;
    let exists = target.symlink_metadata().is_ok();
    if updateOnly && !exists {
        return Err("no user-installed Kinetic.app to update".into());
    }
    if target
        .symlink_metadata()
        .is_ok_and(|meta| !meta.file_type().is_dir())
    {
        return Err("application target is not a directory".into());
    }
    if exists {
        verifyKineticBundle(&target)?;
    }
    let current = installedAppVersion()?;
    if updateOnly && versionParts(&version) <= versionParts(&current) {
        println!("Kinetic {current} is current.");
        return Ok(());
    }
    if !confirm(&format!(
        "{} Kinetic {version} into {}",
        if exists { "Update" } else { "Install" },
        target.display()
    ))? {
        return Err("cancelled".into());
    }
    let archive = TemporaryFile::new("app")?;
    download(&url, &archive.path, maxAppBytes)?;
    if fs::metadata(&archive.path)
        .map_err(|error| error.to_string())?
        .len()
        != size
    {
        return Err("application download size does not match GitHub".into());
    }
    checkDigest(&archive.path, &digest, maxAppBytes)?;
    let parent = target.parent().ok_or("invalid application target")?;
    fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    let binDir = homePath()?.join(".local/bin");
    fs::create_dir_all(&binDir).map_err(|error| error.to_string())?;
    let link = binDir.join("kinetic");
    let expectedTarget = target.join("Contents/Resources/bin/kinetic");
    let createLink = link.symlink_metadata().is_err();
    if !createLink && link.read_link().ok().as_deref() != Some(expectedTarget.as_path()) {
        eprintln!(
            "kinetic: existing CLI path will not be replaced: {}",
            link.display()
        );
    }
    let staging = parent.join(format!(".Kinetic-install-{}", std::process::id()));
    if staging.symlink_metadata().is_ok() {
        return Err("application staging path already exists".into());
    }
    fs::create_dir(&staging).map_err(|error| error.to_string())?;
    let result = (|| {
        let output = Command::new("/usr/bin/ditto")
            .args(["-x", "-k"])
            .arg(&archive.path)
            .arg(&staging)
            .output()
            .map_err(|error| error.to_string())?;
        if !output.status.success() {
            return Err("cannot extract application archive".into());
        }
        let stagedApp = staging.join("Kinetic.app");
        verifyKineticBundle(&stagedApp)?;
        if bundleField(&stagedApp, "CFBundleShortVersionString")? != version {
            return Err("downloaded app and release version do not match".into());
        }
        if !stagedApp.join("Contents/Resources/bin/kinetic").is_file() {
            return Err("downloaded app has no bundled CLI".into());
        }
        let signature = Command::new("/usr/bin/codesign")
            .args(["--verify", "--deep", "--strict"])
            .arg(&stagedApp)
            .status()
            .map_err(|error| error.to_string())?;
        if !signature.success() {
            return Err("downloaded app signature is invalid".into());
        }
        let backup = parent.join(format!(".Kinetic-previous-{}", std::process::id()));
        if exists {
            fs::rename(&target, &backup)
                .map_err(|error| format!("cannot stage current app: {error}"))?;
        }
        if let Err(error) = fs::rename(&stagedApp, &target) {
            if exists {
                let _ = fs::rename(&backup, &target);
            }
            return Err(format!("cannot install app: {error}"));
        }
        if createLink {
            if let Err(error) = std::os::unix::fs::symlink(&expectedTarget, &link) {
                eprintln!("kinetic: app installed, but CLI link could not be created: {error}");
            }
        }
        if exists {
            let recovery = homePath()?
                .join(".Trash")
                .join(format!("Kinetic-{version}-previous.app"));
            if fs::create_dir_all(recovery.parent().ok_or("invalid Trash path")?).is_ok()
                && recovery.symlink_metadata().is_err()
                && fs::rename(&backup, &recovery).is_ok()
            {
                println!("Previous app retained at {}", recovery.display());
            } else {
                println!("Previous app retained at {}", backup.display());
            }
        }
        Ok(())
    })();
    let _ = fs::remove_dir_all(&staging);
    result?;
    println!(
        "Kinetic {version} installed at {}. Relaunch the app.",
        target.display()
    );
    Ok(())
}

fn appUninstall() -> Result<(), String> {
    let target = appRoot()?;
    if !target
        .symlink_metadata()
        .is_ok_and(|meta| meta.file_type().is_dir())
    {
        return Err("user-installed Kinetic.app was not found".into());
    }
    verifyKineticBundle(&target)?;
    if !confirm("Move user-installed Kinetic.app to Trash? Settings and plugins will remain")? {
        return Err("cancelled".into());
    }
    let trash = homePath()?.join(".Trash/Kinetic.app");
    if trash.symlink_metadata().is_ok() {
        return Err("Trash already contains Kinetic.app; nothing was removed".into());
    }
    fs::create_dir_all(trash.parent().ok_or("invalid Trash path")?)
        .map_err(|error| error.to_string())?;
    fs::rename(&target, &trash).map_err(|error| format!("cannot move app to Trash: {error}"))?;
    let link = homePath()?.join(".local/bin/kinetic");
    if link.read_link().ok().as_deref()
        == Some(target.join("Contents/Resources/bin/kinetic").as_path())
    {
        fs::remove_file(&link)
            .map_err(|error| format!("app moved, but CLI link remains: {error}"))?;
    }
    println!("Kinetic.app moved to Trash. ~/.kinetic settings and plugins were preserved.");
    Ok(())
}

pub fn run() -> i32 {
    let args: Vec<String> = env::args().skip(1).filter(|arg| arg != "--yes").collect();
    let result = match args.as_slice() {
        [scope, command] if scope == "plugins" && command == "list" => pluginList(false),
        [scope, command, format] if scope == "plugins" && command == "list" && format == "--json" => pluginList(true),
        [scope, command, id] if scope == "plugins" && command == "install" => pluginInstall(id, false),
        [scope, command, id] if scope == "plugins" && command == "update" => pluginInstall(id, true),
        [scope, command, id] if scope == "plugins" && command == "uninstall" => pluginUninstall(id),
        [scope, command] if scope == "app" && command == "check" => appCheck(),
        [scope, command] if scope == "app" && command == "install" => appInstall(false),
        [scope, command] if scope == "app" && command == "update" => appInstall(true),
        [scope, command] if scope == "app" && command == "uninstall" => appUninstall(),
        _ => Err("usage: kinetic plugins list|install ID|update ID|uninstall ID | app check|install|update|uninstall".into()),
    };
    match result {
        Ok(()) => 0,
        Err(error) => failure(error),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn idsCannotEscapePluginDirectory() {
        assert!(safeId("example.syntax"));
        assert!(!safeId("../outside"));
        assert!(!safeId("a./b"));
        assert!(!safeId("a..b"));
    }

    #[test]
    fn versionsAreStrictTriples() {
        assert!(versionParts("0.23.0") > versionParts("0.22.99"));
        assert_eq!(versionParts("v0.23.0"), None);
        assert_eq!(versionParts("0.23.0-beta"), None);
    }
}
