# Shared Git helpers for Benshell project controllers.

project_git_say() {
  print -- "$*"
}

project_git_die() {
  local label="$1"
  shift
  print -u2 -- "$label: $*"
  return 1
}

project_git_parse_remote_arg() {
  local label="$1"
  shift

  PROJECT_GIT_REMOTE_ARG=""

  while (( $# > 0 )); do
    case "$1" in
      -r|--remote)
        (( $# >= 2 )) || {
          print -u2 -- "$label: $1 requires a remote name"
          return 2
        }
        PROJECT_GIT_REMOTE_ARG="$2"
        shift 2
        ;;
      --remote=*)
        PROJECT_GIT_REMOTE_ARG="${1#--remote=}"
        shift
        ;;
      *)
        if [[ -z "$PROJECT_GIT_REMOTE_ARG" ]]; then
          PROJECT_GIT_REMOTE_ARG="$1"
          shift
        else
          print -u2 -- "$label: unknown git option: $1"
          return 2
        fi
        ;;
    esac
  done
}

project_git_preflight() {
  local repo="$1"
  local label="$2"

  [[ -d "$repo" ]] || project_git_die "$label" "$repo does not exist" || return 1
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
    project_git_die "$label" "$repo is not a Git repository" || return 1
}

project_git_current_branch() {
  local repo="$1"
  git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null
}

project_git_default_remote() {
  local repo="$1"
  local requested="${2:-}"
  local branch remote

  if [[ -n "$requested" ]]; then
    git -C "$repo" remote get-url "$requested" >/dev/null 2>&1 || return 1
    print -- "$requested"
    return 0
  fi

  branch="$(project_git_current_branch "$repo" 2>/dev/null || true)"
  if [[ -n "$branch" ]]; then
    remote="$(git -C "$repo" config --get "branch.$branch.remote" 2>/dev/null || true)"
    if [[ -n "$remote" && "$remote" != "." ]]; then
      if git -C "$repo" remote get-url "$remote" >/dev/null 2>&1; then
        print -- "$remote"
        return 0
      fi
    fi
  fi

  if git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    print -- "origin"
    return 0
  fi

  git -C "$repo" remote | sed -n '1p'
}

project_git_remote_branch_ref() {
  local repo="$1"
  local remote="$2"
  local branch="$3"
  local ref="refs/remotes/$remote/$branch"

  git -C "$repo" show-ref --verify --quiet "$ref" || return 1
  print -- "$remote/$branch"
}

project_git_remote_url() {
  local repo="$1"
  local remote="$2"
  git -C "$repo" remote get-url "$remote" 2>/dev/null || true
}

project_git_show_status() {
  local repo="$1"
  local label="$2"
  local env_remote="${3:-}"
  shift 3

  project_git_parse_remote_arg "$label" "$@" || return $?
  local requested="${PROJECT_GIT_REMOTE_ARG:-$env_remote}"

  project_git_preflight "$repo" "$label" || return $?

  local branch remote remote_ref counts ahead behind
  branch="$(project_git_current_branch "$repo" 2>/dev/null || true)"
  remote="$(project_git_default_remote "$repo" "$requested" 2>/dev/null || true)"

  project_git_say "$label"
  project_git_say "  path: $repo"
  if [[ -n "$branch" ]]; then
    project_git_say "  branch: $branch"
  else
    project_git_say "  branch: detached HEAD"
  fi

  if [[ -n "$remote" ]]; then
    project_git_say "  remote: $remote ($(project_git_remote_url "$repo" "$remote"))"
    if [[ -n "$branch" ]] && remote_ref="$(project_git_remote_branch_ref "$repo" "$remote" "$branch" 2>/dev/null)"; then
      counts="$(git -C "$repo" rev-list --left-right --count "HEAD...$remote_ref")"
      local -a parts
      parts=(${=counts})
      ahead="${parts[1]:-0}"
      behind="${parts[2]:-0}"
      project_git_say "  divergence: ahead $ahead, behind $behind"
    else
      project_git_say "  divergence: remote branch not found locally; run sync to fetch/push"
    fi
  else
    project_git_say "  remote: none"
  fi

  project_git_say ""
  git -C "$repo" status --short --branch
}

project_git_pull() {
  local repo="$1"
  local label="$2"
  local env_remote="${3:-}"
  shift 3

  project_git_parse_remote_arg "$label" "$@" || return $?
  local requested="${PROJECT_GIT_REMOTE_ARG:-$env_remote}"

  project_git_preflight "$repo" "$label" || return $?

  local branch remote remote_ref
  branch="$(project_git_current_branch "$repo" 2>/dev/null || true)"
  [[ -n "$branch" ]] || project_git_die "$label" "cannot pull while HEAD is detached" || return 1

  remote="$(project_git_default_remote "$repo" "$requested" 2>/dev/null || true)"
  [[ -n "$remote" ]] || project_git_die "$label" "no Git remote configured" || return 1

  project_git_say "$label: fetching $remote"
  git -C "$repo" fetch --prune "$remote"

  remote_ref="$(project_git_remote_branch_ref "$repo" "$remote" "$branch" 2>/dev/null || true)"
  [[ -n "$remote_ref" ]] || {
    project_git_say "$label: $remote/$branch does not exist yet; nothing to pull"
    return 0
  }

  project_git_say "$label: rebasing local $branch on $remote/$branch"
  git -C "$repo" pull --rebase --autostash "$remote" "$branch"
}

project_git_push() {
  local repo="$1"
  local label="$2"
  local env_remote="${3:-}"
  shift 3

  project_git_parse_remote_arg "$label" "$@" || return $?
  local requested="${PROJECT_GIT_REMOTE_ARG:-$env_remote}"

  project_git_preflight "$repo" "$label" || return $?

  local branch remote dirty
  branch="$(project_git_current_branch "$repo" 2>/dev/null || true)"
  [[ -n "$branch" ]] || project_git_die "$label" "cannot push while HEAD is detached" || return 1

  remote="$(project_git_default_remote "$repo" "$requested" 2>/dev/null || true)"
  [[ -n "$remote" ]] || project_git_die "$label" "no Git remote configured" || return 1

  dirty="$(git -C "$repo" status --porcelain)"
  if [[ -n "$dirty" ]]; then
    project_git_say "$label: working tree has uncommitted changes; push will only send committed history"
  fi

  project_git_say "$label: pushing HEAD to $remote/$branch"
  git -C "$repo" push -u "$remote" "HEAD:$branch"
}

project_git_sync() {
  local repo="$1"
  local label="$2"
  local env_remote="${3:-}"
  shift 3

  project_git_parse_remote_arg "$label" "$@" || return $?
  local requested="${PROJECT_GIT_REMOTE_ARG:-$env_remote}"

  project_git_preflight "$repo" "$label" || return $?

  local branch remote remote_ref dirty counts ahead behind
  branch="$(project_git_current_branch "$repo" 2>/dev/null || true)"
  [[ -n "$branch" ]] || project_git_die "$label" "cannot sync while HEAD is detached" || return 1

  remote="$(project_git_default_remote "$repo" "$requested" 2>/dev/null || true)"
  [[ -n "$remote" ]] || project_git_die "$label" "no Git remote configured" || return 1

  dirty="$(git -C "$repo" status --porcelain)"
  if [[ -n "$dirty" ]]; then
    project_git_say "$label: working tree has uncommitted changes; pull uses --autostash, push only sends committed history"
  fi

  project_git_say "$label: fetching $remote"
  git -C "$repo" fetch --prune "$remote"

  remote_ref="$(project_git_remote_branch_ref "$repo" "$remote" "$branch" 2>/dev/null || true)"
  if [[ -n "$remote_ref" ]]; then
    counts="$(git -C "$repo" rev-list --left-right --count "HEAD...$remote_ref")"
    local -a parts
    parts=(${=counts})
    ahead="${parts[1]:-0}"
    behind="${parts[2]:-0}"

    if (( behind > 0 )); then
      project_git_say "$label: pulling $behind remote commit(s) with rebase"
      git -C "$repo" pull --rebase --autostash "$remote" "$branch"
      remote_ref="$(project_git_remote_branch_ref "$repo" "$remote" "$branch" 2>/dev/null || true)"
    else
      project_git_say "$label: local branch is not behind $remote/$branch"
    fi

    ahead="$(git -C "$repo" rev-list --count "$remote_ref..HEAD")"
    if (( ahead > 0 )); then
      project_git_say "$label: pushing $ahead local commit(s)"
      git -C "$repo" push -u "$remote" "HEAD:$branch"
    else
      project_git_say "$label: no committed local changes to push"
    fi
  else
    project_git_say "$label: $remote/$branch does not exist yet; pushing current branch"
    git -C "$repo" push -u "$remote" "HEAD:$branch"
  fi

  if [[ -n "$dirty" ]]; then
    project_git_say "$label: uncommitted files remain local; commit them before they can sync to GitHub"
  fi
}
