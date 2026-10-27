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
