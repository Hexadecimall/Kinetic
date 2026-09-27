# GitHub accounts

Kinetic's top-right titlebar control opens a Kinetic-drawn account panel on Home and in the editor.
Signing in requests a short-lived code from GitHub. The panel displays that code and opens only
GitHub's official verification page in the user's browser. Kinetic polls at GitHub's required
interval, validates the returned profile, and shows the signed-in name, login, and avatar. The authorization flow is
available to any GitHub user; it is not tied to the account that registered Kinetic's OAuth app.

The public OAuth client ID is embedded in the app bundle. There is no bundled client secret and no
reuse of the user's Git command-line credentials. Sign-in currently requests `repo` plus
`offline_access`. GitHub's `repo` scope permits read and write access to public and private
repositories, including some organization-owned resources. A user or organization can restrict
the access it grants. Kinetic uses the token only to load the signed-in profile in this release;
source-control operations and plugin publishing through the account are later features. This
release does not request `delete_repo`, `workflow`, or account-administration scopes.

The public OAuth badge asset is `assets/icons/KineticOAuth.png`, generated alongside the app icon
from the Kinetic SVG by `scripts/generate-icons`. Its navy canvas matches the OAuth app's badge
background color (`#151E2C`).

The access and refresh tokens live only in the macOS Keychain under Kinetic's own service name;
they are never written to `~/.kinetic/`, project files, or logs. Expiring tokens are refreshed on
launch. Signing out deletes Kinetic's local Keychain session and stops in-progress polling. It
does not revoke a token on GitHub's servers; users can revoke Kinetic Editor from GitHub's
authorized-app settings. Kinetic does not silently start a new authorization after sign-out.

The account surface is intentionally one active GitHub account for now. Multi-account switching,
repository listing, and Git operations require separate UI and capability work.
