# Releasing

Releases go out from GitHub Actions through [RubyGems trusted publishing](https://guides.rubygems.org/trusted-publishing/):
the workflow trades a GitHub OIDC token for a short-lived RubyGems key, so no API key is stored anywhere.

## One-time setup

1. **GitHub repository**: `github.com/Largo/ruby_llm-providers-infomaniak`, private until the first
   gem is on rubygems.org (trusted publishing works from private repos), then made public so the
   gem's source and changelog links resolve:

   ```sh
   gh repo create Largo/ruby_llm-providers-infomaniak --private --source . --push
   # after the first release:
   gh repo edit Largo/ruby_llm-providers-infomaniak --visibility public --accept-visibility-change-consequences
   ```
2. **GitHub environment**: Settings > Environments > New environment, named `release`.
   Optionally add a deployment rule limiting it to tags `v*`, and required reviewers.
3. **Pending trusted publisher on rubygems.org** (the gem does not exist yet, so it is a *pending* one):
   <https://rubygems.org/profile/oidc/pending_trusted_publishers> > Create

   | Field | Value |
   |---|---|
   | Gem name | `ruby_llm-providers-infomaniak` |
   | Trusted publisher type | GitHub Actions |
   | Repository owner | `Largo` |
   | Repository name | `ruby_llm-providers-infomaniak` |
   | Workflow filename | `release.yml` |
   | Environment | `release` |

   After the first successful push it becomes a regular trusted publisher of the gem
   (Gem page > Trusted publishers).

## Each release

1. Bump `VERSION` in `lib/ruby_llm/providers/infomaniak/version.rb` and add a section to `CHANGELOG.md`.
2. Check the prices on <https://www.infomaniak.com/en/hosting/ai-services/prices> against
   `lib/ruby_llm/providers/infomaniak/pricing.rb` (update `AS_OF` too), then refresh the model catalog:
   `bundle exec rake models` (needs `test/.env`), and commit `models.json`.
3. Commit, then tag and push:

   ```sh
   git tag v0.1.0
   git push origin main v0.1.0
   ```

The `release` workflow checks that the tag matches the gem version, runs the tests, publishes the gem
with `rubygems/release-gem`, and creates a GitHub release with the built `.gem` attached.
