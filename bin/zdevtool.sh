#!/bin/zsh

# Make sure there's no other script using the same env name
# <PROJECT>_ENV_CURRENT
# <PROJECT>_ENV_PENDING

devtool() {
  CONFIG_FILE=devtool.config
  LOCK_FILE=env.lock
  COMMON_ENV_TEMPLATE_NAME=common
  SELECTABLE_ENV_TEMPLATE_NAME=selectable

  # load config
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: please run from the project root with \"$CONFIG_FILE\""
    return 1
  fi
  source "$CONFIG_FILE"
  
  local missing_vars=("PROJECT" "VALID_ENV_TARGETS" "DEFAULT_ENV_TARGET" "BASE_DB_ENV_TARGET" "OP_ACCOUNT" "ENV_TEMPLATE_PATH" "COMMON_ENV_OUTPUT_PATH")
  for var in "${missing_vars[@]}"; do
    if [[ -z ${(P)var} ]]; then
      echo "ERROR: missing \"\$$var\""
      return 1
    fi
  done

  ENV_CURRENT_VAR_NAME="${PROJECT}_ENV_CURRENT"
  ENV_PENDING_VAR_NAME="${PROJECT}_ENV_PENDING"

  # execution
  if [[ "$1" == 'env' ]]; then
    case "$2" in
      'fetch_vars_internal')
        local env_fetch_vars_internal_env_var_target=$3
        local env_fetch_vars_internal_output_file=$4
        
        if [[ -f "$env_fetch_vars_internal_output_file" ]]; then
          return 0
        fi
        
        if ! command -v op >/dev/null; then
          echo "ERROR: please install 1password cli: https://developer.1password.com/docs/cli/get-started/"
          return 1
        fi
        
        if ! op whoami >/dev/null 2>&1; then
          eval "$(op signin --account $OP_ACCOUNT)"
        fi
        
        op inject -i "$ENV_TEMPLATE_PATH/$env_fetch_vars_internal_env_var_target" -o "$env_fetch_vars_internal_output_file"
        
        if [[ $? -ne 0 ]]; then
          echo "ERROR: Failed to create \"$env_fetch_vars_internal_env_var_target\" env file \"$env_fetch_vars_internal_output_file\""
          return 1
        fi
        return 0
        ;;
      'get')
        echo "INFO: $ENV_CURRENT_VAR_NAME=${(P)ENV_CURRENT_VAR_NAME}"
        return 0
        ;;
      'set')
        local env_set_env_target=$3
        $0 env get
        if [[ -z "$env_set_env_target" ]]; then
          return 0
        fi
        
        if ! [[ " ${VALID_ENV_TARGETS[@]} " =~ " $env_set_env_target " ]]; then
          echo "ERROR: Invalid env target \"$env_set_env_target\""
          return 1
        fi
        
        $0 env fetch_vars_internal "$COMMON_ENV_TEMPLATE_NAME" "$COMMON_ENV_OUTPUT_PATH"
        [[ $? -ne 0 ]] && return 1
        
        export "$ENV_PENDING_VAR_NAME=$env_set_env_target"
        $0 env fetch_vars_internal "$SELECTABLE_ENV_TEMPLATE_NAME" "${(P)ENV_PENDING_VAR_NAME}.env"
        [[ $? -ne 0 ]] && return 1
        
        set -a
        source "${(P)ENV_PENDING_VAR_NAME}.env"
        source "$COMMON_ENV_OUTPUT_PATH"
        set +a
        
        export "$ENV_CURRENT_VAR_NAME=${(P)ENV_PENDING_VAR_NAME}"
        export "$ENV_PENDING_VAR_NAME="
        $0 env get
        return 0
        ;;
      'lock')
        local env_lock_env_target=$3
        [[ -z "$env_lock_env_target" ]] && echo "ERROR: Missing env target" && return 1
        $0 env set "$env_lock_env_target"
        [[ $? -ne 0 ]] && return 1
        echo "${(P)ENV_CURRENT_VAR_NAME}" > "$LOCK_FILE"
        return 0
        ;;
      'restore')
        if [[ ! -f "$LOCK_FILE" ]]; then
          $0 env lock "$DEFAULT_ENV_TARGET"
        else
          $0 env set "$(cat "$LOCK_FILE")"
        fi
        return 0
        ;;
      'reset_vars')
        echo "This will delete \".env.local\" and \"*.env\". Are you sure? [yes/no]"
        read -r answer
        if [[ "$answer" == 'yes' ]]; then
          rm -f .env.local
          rm -f *.env
          $0 env restore
        fi
        return 0
        ;;
    esac
  elif [[ "$1" == 'cred' ]]; then
    if [[ -z "$DATABAG_JSON_PATH" || -z "$DATABAG_PASSWORD_VAR_NAME" ]]; then
      echo "ERROR: Missing required credentials configuration"
      return 1
    fi
    local cred_databag_password="${(P)DATABAG_PASSWORD_VAR_NAME}"
    case "$2" in
      'get')
        local cred_get_key=$3
        [[ -z "$cred_get_key" ]] && echo "ERROR: missing key argument" && return 1
        npx databag -- --file="$DATABAG_JSON_PATH" --password="$cred_databag_password" --key="$cred_get_key"
        return 0
        ;;
      'set')
        local cred_set_key=$3
        local cred_set_value=$4
        [[ -z "$cred_set_key" || -z "$cred_set_value" ]] && echo "ERROR: missing key or value argument" && return 1
        npx databag -- --file="$DATABAG_JSON_PATH" --password="$cred_databag_password" --key="$cred_set_key" --value="$cred_set_value"
        return 0
        ;;
      'setf')
        local cred_set_key=$3
        local cred_set_file=$4
        [[ -z "$cred_set_key" || -z "$cred_set_file" ]] && echo "ERROR: missing key or file path argument" && return 1
        npx databag -- --file="$DATABAG_JSON_PATH" --password="$cred_databag_password" --key="$cred_set_key" --value-file="$cred_set_file"
        return 0
        ;;
    esac
  fi

  echo "Usage: $0 <command> <args>"
}
