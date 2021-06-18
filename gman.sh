[ -e '/etc/gmanrc' ] && . '/etc/gmanrc'
[ -e "${HOME}/.gmanrc" ] && . "${HOME}/.gmanrc"

error() {
  echo -e "\033[31m$*\033[0m" >&2
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
}

gman-folder-unknown() {
  error "Unknown command [${1}]"
  command-usage 'gman' 'folder' 'find' 'FOLDER_NAME'
  command-usage 'gman' 'folder' 'children' 'FOLDER_ID'
}

gman-folder-find() {
  folder_name="${1}"

  if [ -z "${folder_name}" ]; then
    error 'No folder name given!'
    command-usage 'gman' 'folder' 'find' 'FOLDER_NAME'
    return 1
  fi

  folders_resp=$(gcloud resource-manager folders list \
    --organization="${e11_organization}" \
    --configuration="${e11_service_configuration}" \
    --format=json)

  if [ $? -ne 0 ]; then
    error "Cannot retrieve folder list"
    diagnostic "${folders_resp}"
    return 1
  fi

  resource_string=$(echo "${folders_resp}" | jq -Mr '.[] | select(.displayName == "'${folder_name}'") | .name')

  if [ $? -ne 0 ] || [ -z "${resource_string}" ]; then
    error "No folder found named [${folder_name}]."
    return 1
  fi

  echo "${resource_string##folders/}"
}

gman-folder-children() {
  FOLDER_ID="${1}"
  if [ -z "${FOLDER_ID}" ]; then
    command-usage 'gman folder children FOLDER_ID'
    return 1
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
    find) gman-folder-find "$@";;
    *) gman-folder-unknown "${cmd}";;
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
    *) category-unknown "${category}"; return 1;;
  esac
}

