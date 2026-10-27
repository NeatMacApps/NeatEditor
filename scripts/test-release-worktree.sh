#!/bin/bash
# Exercise the publisher's actual clean-tree guard without signing or remote writes.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture}"' EXIT
checker="${fixture}/check.sh"
printf '%s\n' '#!/bin/bash' 'set -euo pipefail' 'die() { printf "%s\n" "$*" >&2; exit 1; }' > "${checker}"
awk '/^assert_clean_worktree\(\) \{/{active=1} active{print} active && /^\}/{exit}' \
  "${root}/scripts/publish-release.sh" >> "${checker}"
printf '%s\n' 'assert_clean_worktree' >> "${checker}"

for state in clean modified staged untracked untracked-hidden ignored; do
  repo="${fixture}/${state}"
  mkdir "${repo}"
  (
    cd "${repo}"
    git init -q
    printf 'original\n' > tracked.txt
    printf 'build/\n' > .gitignore
    git add tracked.txt .gitignore
    git -c user.name='Release Test' -c user.email='release-test@example.invalid' \
      commit -qm 'Initial test fixture'
    case "${state}" in
      modified) printf 'changed\n' >> tracked.txt ;;
      staged) printf 'changed\n' >> tracked.txt; git add tracked.txt ;;
      untracked|untracked-hidden) printf 'draft\n' > draft.txt
        if [[ "${state}" == untracked-hidden ]]; then
          git config status.showUntrackedFiles no
        fi ;;
      ignored) mkdir build; printf 'artifact\n' > build/output.txt ;;
    esac
    before_head="$(git rev-parse HEAD)"
    before_status="$(git status --porcelain --untracked-files=all)"
    result=0
    /bin/bash "${checker}" > "${fixture}/${state}.log" 2>&1 || result=$?
    case "${state}" in
      clean|ignored) [[ "${result}" -eq 0 ]] ;;
      *) [[ "${result}" -ne 0 ]] ;;
    esac
    # Refusal must leave both staged and unstaged work and history untouched.
    [[ "$(git rev-parse HEAD)" == "${before_head}" ]]
    [[ "$(git status --porcelain --untracked-files=all)" == "${before_status}" ]]
    printf 'PASS %s (exit %s; history and working tree unchanged)\n' "${state}" "${result}"
  )
done

mkdir "${fixture}/not-a-repository"
if (cd "${fixture}/not-a-repository" && /bin/bash "${checker}" > "${fixture}/not-a-repository.log" 2>&1); then
  printf 'FAIL guard accepted a non-repository\n' >&2
  exit 1
fi
printf 'PASS non-repository rejected\n'

# Run the actual appcast commit block with push stubbed; no remote is contacted.
appcast_block="${fixture}/appcast.sh"
awk '/^git add /{active=1} active && /^asset_url=/{exit} active{print}' \
  "${root}/scripts/publish-release.sh" > "${appcast_block}"
(
  mkdir "${fixture}/appcast"
  cd "${fixture}/appcast"
  git init -q
  git config user.name 'Release Test'
  git config user.email 'release-test@example.invalid'
  printf 'old feed\n' > appcast.xml
  printf 'original\n' > unrelated.txt
  git add appcast.xml unrelated.txt
  git commit -qm 'Initial appcast fixture'
  printf 'new feed\n' > appcast.xml
  printf 'unfinished work\n' > unrelated.txt
  git add unrelated.txt
  APPCAST_PATH="${PWD}/appcast.xml"
  DEFAULT_BRANCH=main
  version=test
  git() {
    if [[ "$1" == push ]]; then return 0; fi
    command git "$@"
  }
  source "${appcast_block}"
  [[ "$(git diff-tree --no-commit-id --name-only -r HEAD)" == appcast.xml ]]
  [[ "$(git diff --cached --name-only)" == unrelated.txt ]]
  [[ "$(git show :unrelated.txt)" == 'unfinished work' ]]
  before_head="$(git rev-parse HEAD)"
  source "${appcast_block}"
  [[ "$(git rev-parse HEAD)" == "${before_head}" ]]
  [[ "$(git diff --cached --name-only)" == unrelated.txt ]]
  printf 'PASS appcast-only commit and no-op preserve unrelated staged work\n'
)
