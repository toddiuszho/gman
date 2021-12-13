[ -e '/etc/gmanrc' ] && . '/etc/gmanrc'
[ -e "${HOME}/.gmanrc" ] && . "${HOME}/.gmanrc"

error() {
  echo -e "\033[31m[ERROR] $*\033[0m" >&2
}

info() {
  echo -e "\033[35m[INFO] $*\033[0m" >&2
}

diagnostic() {
  if [ $# -lt 2 ]; then
    echo "Cannot do diagnostic for $1" >&2
  fi

  echo -e "\nDiagnostic for [$1]" >&2
  shift 1
  echo -e "\033[32m$*\033[0m" >&2
}

command-usage() {
  echo -e "Command Usage: \033[33m$*\033[0m" >&2
}

category-unknown() {
  error "Unknown category: [${1}]"
  echo '' >&2
  echo '  Categories: folder project secrets' >&2
}

OS="$(uname)"
OS="${OS,,}"

is-macos() {
  [ "${OS}" = 'darwin' ]
}

is-linux() {
  [ "${OS}" = 'linux' ]
}

is-windows() {
  [ "${OS}" = 'windows' ]
}

is-cygwin() {
  [ "${OS}" = 'cygwin' ]
}

if is-macos; then

  # awk
  if [ -z "${CMD_AWK}" ]; then
    type gawk >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      CMD_AWK="$(which gawk)"
    else
      error "Must install GNU grep with 'brew install gawk'"
      exit 1
    fi
  fi

fi

CMD_AWK="${CMD_AWK:-/usr/bin/awk}"

gman-folder-unknown() {
  error "Unknown command [${1}]"
  command-usage 'gman' 'folder' 'find' 'FOLDER_NAME'
  command-usage 'gman' 'folder' 'children' 'FOLDER_ID'
  command-usage 'gman' 'folder' 'list'
}

gman-folder-list() {
  gcloud resource-manager folders list \
    --organization="${e11_organization}" \
    --configuration="${e11_service_configuration}"
}

gman-folder-find() {
  folder_name="${1}"

  if [ -z "${folder_name}" ]; then
    error 'No folder name given!'
    command-usage 'gman' 'folder' 'find' 'FOLDER_NAME'
    return 1
  fi

  maybe="${folder_aliases[$folder_name]}"
  [ -n "${maybe}" ] && folder_name="${maybe}"

  folders_resp="$(gcloud resource-manager folders list \
    --organization="${e11_organization}" \
    --configuration="${e11_service_configuration}" \
    --filter=displayName=${folder_name} \
    --format='get(name)')"

  if [ $? -ne 0 ]; then
    error "Cannot retrieve folder list"
    diagnostic "${folders_resp}"
    return 1
  fi

  basename "${folders_resp}"
}

gman-folder-children() {
  FOLDER_ID="${1}"
  if [ -z "${FOLDER_ID}" ]; then
    command-usage 'gman folder children FOLDER_ID'
    return 1
  fi

  if [ -n "$(echo "${FOLDER_ID}" | tr -d '0-9')" ]; then
    LOOKUP="$(gman folder find "$@")"
    if [ $? -eq 0 ] && [ -n "${LOOKUP}" ]; then
      info "Looked up folder name [${FOLDER_ID}] to use folder ID [${LOOKUP}]."
      FOLDER_ID="${LOOKUP}"
    fi
  fi

  gcloud projects list \
    --filter " parent.id: '${FOLDER_ID}' " \
    --configuration="${e11_service_configuration}"
}

gman-folder() {
  cmd="${1}"
  shift 1
  case "${cmd}" in
    children) gman-folder-children "$@";;
    describe) gman-folder-children "$@";;
    find) gman-folder-find "$@";;
    info) gman-folder-children "$@";;
    list) gman-folder-list;;
    *) gman-folder-unknown "${cmd}";;
  esac
}

gman-project-unknown() {
  error "Unknown command [${1}]"
  command-usage 'gman' 'project' 'find' 'PROJECT_NAME'
}

gman-project-find() {
  local PROJECT_NAME="${1}"
  gcloud projects list \
    --filter=name=${PROJECT_NAME} \
    --configuration="${e11_service_configuration}"
}

gman-project() {
  cmd="${1}"
  shift 1
  case "${cmd}" in
    find) gman-project-find "$@";;
    *) gman-project-unknown "${cmd}";;
  esac
}

gman-secrets-unknown() {
  error "Unknown command [${1}]"
  command-usage 'gman' 'secrets' 'list' 'FOLDER_NAME [REGEX]'
  command-usage 'gman' 'secrets' 'spread' 'FOLDER_NAME' 'SECRET_NAME'
}

gman-project-map-copypasta() {
  projs="$(gcloud projects list \
    --filter=parent.id=${FOLDER_ID} \
    --configuration="${e11_service_configuration}" \
    --format='get(projectId, projectNumber)'
  )"
  if [ $? -ne 0 ]; then
    echo "Could not get [${LOOKUP}] -> [${FOLDER_ID}] project list"
    return 1
  fi
  declare -A sProjMapLines="$(  echo "${projs}" | "${CMD_AWK}" '{ print "[" $1 "]=" $2 }'  )"
  sProjMap="declare -A projMap=(${sProjMapLines})"
  eval "${sProjMap}"
}

gman-secrets-list() {
  local FOLDER_ID="${1}"
  if [ -z "${FOLDER_ID}" ]; then
    command-usage 'gman secrets list FOLDER_ID'
    return 1
  fi
  shift 1

  secret_filter_opt=''
  if [ -n "$1" ] && [ "${1:0:2}" != '--' ];  then
    secret_filter_opt="--filter=name~$1"
    shift 1
  fi

  LOOKUP="$(gman folder find "${FOLDER_ID}")"
  if [ $? -eq 0 ] && [ -n "${LOOKUP}" ]; then
    info "Looked up folder name [${FOLDER_ID}] to use as parent folder ID [${LOOKUP}]."
  fi

  projs="$(gcloud projects list \
    --filter=parent.id=${LOOKUP} \
    --configuration="${e11_service_configuration}" \
    --format='get(projectId)'
  )"
  if [ $? -ne 0 ]; then
    echo "Could not get [${LOOKUP}] -> [${FOLDER_ID}] project list"
    return 1
  fi
  declare -a projIds=(${projs})
  for project_id in "${projIds[@]}"; do
    echo -e "\n\033[35m${project_id}\n--------------------\033[0m"
    gcloud secrets list --project=${project_id} ${secret_filter_opt} "$@"
  done
}

gman-secrets-spread() {
  local FOLDER_ID="${1}"
  local SECRET_NAME="${2}"
  if [ -z "${FOLDER_ID}" ] || [ -z "${SECRET_NAME}" ]; then
    command-usage 'gman secrets spread FOLDER_ID SECRET_NAME'
    return 1
  fi
  shift 2

  LOOKUP="$(gman folder find "${FOLDER_ID}")"
  if [ $? -eq 0 ] && [ -n "${LOOKUP}" ]; then
    info "Looked up folder name [${FOLDER_ID}] to use as parent folder ID [${LOOKUP}]."
  fi

  secret_file_path="${HOME}/${FOLDER_ID}/${SECRET_NAME}"
  if ! [ -f "${secret_file_path}" ]; then
    echo "Could find file data file at [${secret_file_path}]" >&2
    return 1
  fi

  projs="$(gcloud projects list \
    --filter=parent.id=${LOOKUP} \
    --configuration="${e11_service_configuration}" \
    --format='get(projectId, projectNumber)'
  )"
  if [ $? -ne 0 ]; then
    echo "Could not get [${LOOKUP}] -> [${FOLDER_ID}] project list"
    return 1
  fi
  declare -A sProjMapLines="$(  echo "${projs}" | "${CMD_AWK}" '{ print "[" $1 "]=" $2 }'  )"
  sProjMap="declare -A projMap=(${sProjMapLines})"
  eval "${sProjMap}"
  for project_id in "${!projMap[@]}"; do
    project_number="${projMap[$project_id]}"
    slcap="$(gcloud secrets list --filter="name~${SECRET_NAME}" --project=${project_id} "$@" 2>/dev/null)"
    if [ -z "${slcap}" ]; then
      gcloud secrets create "${SECRET_NAME}" --project=${project_id} "$@"
      [ $? -ne 0 ] && continue
    fi
    vcap="$(gcloud secrets versions list "${SECRET_NAME}" --project=${project_id} "$@" 2>/dev/null)"
    if [ -z "${vcap}" ]; then
      gcloud secrets versions add "${SECRET_NAME}" --data-file="${secret_file_path}" --project=${project_id} "$@"
    fi
  done
}

gman-secrets() {
  cmd="${1}"
  shift 1
  case "${cmd}" in
    list) gman-secrets-list "$@";;
    spread) gman-secrets-spread "$@";;
    *) gman-secrets-unknown "${cmd}";;
  esac
}

gman() {
  category="${1}"
  if [ -z "${category}" ]; then
    command-usage 'gman' 'CATEGORY' 'COMMAND' '[ARGS...]'
    return 1
  fi

  shift 1
  case "${category}" in
    folder) gman-folder "$@";;
    project) gman-project "$@";;
    secrets) gman-secrets "$@";;
    *) category-unknown "${category}"; return 1;;
  esac
}

