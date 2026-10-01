# Notarization preflight rejected by an account agreement

On 2026-10-01, the release preflight for the locally installed 1.0.4 (3)
build failed at `notarytool history`: HTTP 403, with the service reporting
that a required agreement was missing or had expired. The service did
not identify which agreement; the account portal's agreement status was
not inspected. No notarization submission or public package release was
completed by this attempt. The pin alignment fix was already built from
committed source, installed locally, and verified in the actual window.

The account holder must inspect the pending agreements in the Apple
Developer account. Apple documents that updated program agreements must
be reviewed and accepted by the account holder in its
[roles guide](https://developer.apple.com/help/account/access/roles).
Do not replace credentials, re-sign the app, or repeatedly upload a
package to resolve an agreement rejection.

After the account restriction is resolved, rerun
`scripts/publish-release.sh --dry-run`, then the documented release
route in [RELEASING.md](../../RELEASING.md). Successful local launch
does not establish that a publicly notarized package exists.
