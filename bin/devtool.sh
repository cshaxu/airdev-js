#!/bin/bash

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
  if [[ "$PROJECT" == "" ]]; then
    echo "ERROR: missing \"\$PROJECT\""
    return 1
  fi
  if [[ "$VALID_ENV_TARGETS" == "" ]]; then
    echo "ERROR: missing \"\$VALID_ENV_TARGETS\""
    return 1
  fi
  if [[ "$DEFAULT_ENV_TARGET" == "" ]]; then
    echo "ERROR: missing \"\$DEFAULT_ENV_TARGET\""
    return 1
  fi
  if [[ "$BASE_DB_ENV_TARGET" == "" ]]; then
    echo "ERROR: missing \"\$BASE_DB_ENV_TARGET\""
    return 1
  fi
  if [[ "$OP_ACCOUNT" == "" ]]; then
    echo "ERROR: missing \"\$OP_ACCOUNT\""
    return 1
  fi
  if [[ "$ENV_TEMPLATE_PATH" == "" ]]; then
    echo "ERROR: missing \"\$ENV_TEMPLATE_PATH\""
    return 1
  fi
  if [[ "$COMMON_ENV_OUTPUT_PATH" == "" ]]; then
    echo "ERROR: missing \"\$COMMON_ENV_OUTPUT_PATH\""
    return 1
  fi

  ENV_CURRENT_VAR_NAME="${PROJECT}_ENV_CURRENT"
  ENV_PENDING_VAR_NAME="${PROJECT}_ENV_PENDING"

  # execution
  if [[ "$1" == 'env' ]]; then
    if [[ "$2" == 'fetch_vars_internal' ]]; then
      # Fetch env vars from 1password
      env_fetch_vars_internal_env_var_target=$3
      env_fetch_vars_internal_output_file=$4
      if [[ -f "$env_fetch_vars_internal_output_file" ]]; then
        return 0
      fi
      # check 1password cli
      if [[ $(which op) == '' ]]; then
        echo ERROR: please install 1password cli: https://developer.1password.com/docs/cli/get-started/
        return 1
      fi
      # login to 1password
      op whoami >/dev/null 2>&1
      if [[ $? -ne 0 ]]; then
        eval $(op signin --account $OP_ACCOUNT)
      fi
      # fetch env vars
      op inject -i $ENV_TEMPLATE_PATH/$env_fetch_vars_internal_env_var_target -o $env_fetch_vars_internal_output_file
      if [[ $? -ne 0 ]]; then
        echo "ERROR: Failed to create "$env_fetch_vars_internal_env_var_target" env file \"$env_fetch_vars_internal_output_file\""
        return 1
      fi
      return 0

    elif [[ "$2" == 'get' ]]; then
      # Get project env in the current session
      echo INFO: $ENV_CURRENT_VAR_NAME=${!ENV_CURRENT_VAR_NAME}
      return 0

    elif [[ "$2" == 'set' ]]; then
      # Set project env in the current session
      env_set_env_target=$3
      $FUNCNAME env get
      if [[ "$env_set_env_target" == '' ]]; then
        return 0
      fi
      is_valid=0
      for i in "${VALID_ENV_TARGETS[@]}"; do
        if [[ "$i" == "$env_set_env_target" ]]; then
          is_valid=1
          break
        fi
      done
      if [[ $is_valid -eq 0 ]]; then
        echo "ERROR: Invalid env target \"$env_set_env_target\""
        return 1
      fi
      if [[ $? -ne 0 ]]; then
        return 1
      fi
      # fetch common env vars
      $FUNCNAME env fetch_vars_internal $COMMON_ENV_TEMPLATE_NAME $COMMON_ENV_OUTPUT_PATH
      if [[ $? -ne 0 ]]; then
        return 1
      fi
      # fetch selected env vars
      eval "export $ENV_PENDING_VAR_NAME=$env_set_env_target"
      $FUNCNAME env fetch_vars_internal $SELECTABLE_ENV_TEMPLATE_NAME ${!ENV_PENDING_VAR_NAME}.env
      if [[ $? -ne 0 ]]; then
        return 1
      fi
      # apply env file of common
      set -o allexport
      source ${!ENV_PENDING_VAR_NAME}.env
      set +o allexport
      # apply env file of selection
      set -o allexport
      source $COMMON_ENV_OUTPUT_PATH
      set +o allexport
      # clean up
      eval "export $ENV_CURRENT_VAR_NAME=${!ENV_PENDING_VAR_NAME}"
      eval "export $ENV_PENDING_VAR_NAME="
      $FUNCNAME env get
      return 0

    elif [[ "$2" == 'lock' ]]; then
      # Lock project env for all sessions
      env_lock_env_target=$3
      if [[ "$env_lock_env_target" == '' ]]; then
        targets1=$(printf "%s/" "${VALID_ENV_TARGETS[@]}")
        targets2=${targets1%/}
        echo "ERROR: Missing env target \"${targets2}\""
        return 1
      fi
      $FUNCNAME env set $env_lock_env_target
      if [[ $? -ne 0 ]]; then
        return 1
      fi
      echo ${!ENV_CURRENT_VAR_NAME} >$LOCK_FILE
      return 0

    elif [[ "$2" == 'restore' ]]; then
      if [[ ! -f "$LOCK_FILE" ]]; then
        $FUNCNAME env lock $DEFAULT_ENV_TARGET
      else
        $FUNCNAME env set $(cat $LOCK_FILE)
      fi
      return 0

    elif [[ "$2" == 'reset_vars' ]]; then
      # reset locally cached env vars
      echo "This will delete \".env.local\" and \"*.env\". Are you sure? [yes/no]"
      read answer
      if [[ "$answer" == 'yes' ]]; then
        rm -f .env.local
        rm -f *.env
        $FUNCNAME env restore
      fi
      return 0
    fi
  elif [[ "$1" == 'cred' ]]; then
    if [[ "$DATABAG_JSON_PATH" == "" ]]; then
      echo "ERROR: missing \"\$DATABAG_JSON_PATH\""
      return 1
    fi
    if [[ "$DATABAG_PASSWORD_VAR_NAME" == "" ]]; then
      echo "ERROR: missing \"\$DATABAG_PASSWORD_VAR_NAME\""
      return 1
    fi

    cred_databag_password="${!DATABAG_PASSWORD_VAR_NAME}"

    if [[ "$2" == 'get' ]]; then
      cred_get_key=$3
      if [[ "$cred_get_key" == '' ]]; then
        echo ERROR: missing key argument
        return 1
      fi
      npx databag -- --file=$DATABAG_JSON_PATH --password=$cred_databag_password --key=$cred_get_key
      return 0

    elif [[ "$2" == 'set' ]]; then
      cred_set_key=$3
      cred_set_value=$4
      if [[ "$cred_set_key" == '' ]]; then
        echo ERROR: missing key argument
        return 1
      fi
      if [[ "$cred_set_value" == '' ]]; then
        echo ERROR: missing value argument
        return 1
      fi
      npx databag -- --file=$DATABAG_JSON_PATH --password=$cred_databag_password --key=$cred_set_key --value=$cred_set_value
      return 0

    elif [[ "$2" == 'setf' ]]; then
      cred_set_key=$3
      cred_set_file=$4
      if [[ "$cred_set_key" == '' ]]; then
        echo ERROR: missing key argument
        return 1
      fi
      if [[ "$cred_set_file" == '' ]]; then
        echo ERROR: missing file path argument
        return 1
      fi
      npx databag -- --file=$DATABAG_JSON_PATH --password=$cred_databag_password --key=$cred_set_key --value-file=$cred_set_file
      return 0
    fi
  elif [[ "$1" == 'db' ]]; then
    if [[ -n "$COCKROACH_DATABASE_URL_VAR_NAME" && -z "$POSTGRES_DATABASE_URL_VAR_NAME" ]]; then
      db_database_url="${!COCKROACH_DATABASE_URL_VAR_NAME}"
    elif [[ -z "$COCKROACH_DATABASE_URL_VAR_NAME" && -n "$POSTGRES_DATABASE_URL_VAR_NAME" ]]; then
      db_database_url="${!POSTGRES_DATABASE_URL_VAR_NAME}"
    else
      echo "ERROR: Exactly one of COCKROACH_DATABASE_URL_VAR_NAME and POSTGRES_DATABASE_URL_VAR_NAME must be set."
      return 1
    fi

    if [[ "$2" == 'view' ]]; then
      # Opens Prisma Studio to view the database
      db_view_env_target=$3
      $FUNCNAME env set $db_view_env_target
      if [[ $? -ne 0 ]]; then
        return 1
      fi
      npx prisma studio
      echo
      $FUNCNAME env restore
      return 0

    elif [[ "$2" == 'pull_schema' ]]; then
      # Refresh local Prisma schema
      $FUNCNAME env set $BASE_DB_ENV_TARGET
      if [[ $? -ne 0 ]]; then
        return 1
      fi
      echo
      npx prisma db pull
      echo
      $FUNCNAME env restore
      return 0

    elif [[ "$2" == 'migration' ]]; then
      if [[ "$3" == 'create' ]]; then
        # Create Prisma db migrate script
        db_migration_create_migration_name=$4
        if [[ "$db_migration_create_migration_name" == '' ]]; then
          echo ERROR: missing migration name argument
          return 1
        fi
        $FUNCNAME env set $BASE_DB_ENV_TARGET
        if [[ $? -ne 0 ]]; then
          return 1
        fi
        echo
        PRISMA_MIGRATIONS_PATH=prisma/migrations
        if [[ ! -d "$PRISMA_MIGRATIONS_PATH" ]]; then
          mkdir -p $PRISMA_MIGRATIONS_PATH
        fi
        PRISMA_SCHEMA_FILE=prisma/schema.prisma
        db_migration_create_timestamp=$(date -u +'%Y%m%d%H%M%S')
        db_migration_create_migration_path=$PRISMA_MIGRATIONS_PATH/$db_migration_create_timestamp\_$db_migration_create_migration_name
        echo INFO: Generating migration \"$db_migration_create_migration_path\" ...
        if [[ ! -d "$db_migration_create_migration_path" ]]; then
          mkdir -p $db_migration_create_migration_path
        fi
        db_migration_create_migration_file=$db_migration_create_migration_path/migration.sql
        npx prisma migrate diff \
          --from-url $db_database_url \
          --to-schema-datamodel $PRISMA_SCHEMA_FILE \
          --script >$db_migration_create_migration_file
        echo
        $FUNCNAME env restore
        return 0

      elif [[ "$3" == 'deploy' ]]; then
        db_migration_deploy_env_target=$4
        # deploy migrations
        if [[ "$db_migration_deploy_env_target" == '' ]]; then
          targets1=$(printf "%s/" "${VALID_ENV_TARGETS[@]}")
          targets2=${targets1%/}
          echo "ERROR: Missing env target \"${targets2}\""
          return 1
        fi
        $FUNCNAME env set $db_migration_deploy_env_target
        if [[ $? -ne 0 ]]; then
          return 1
        fi
        echo
        npx prisma migrate status
        echo
        echo "Are you sure about deploying migrations to \"$db_migration_deploy_env_target\"? [yes/no]"
        read answer
        if [[ "$answer" == 'yes' ]]; then
          npx prisma migrate deploy
        fi
        echo
        $FUNCNAME env restore
        return 0
      fi
    fi

  elif [[ "$1" == 'cockroach' ]]; then
    if [[ "$COCKROACH_DATABASE_URL_VAR_NAME" == "" ]]; then
      echo "ERROR: missing \"\$COCKROACH_DATABASE_URL_VAR_NAME\""
      return 1
    fi

    if [[ "$2" == 'sql' ]]; then
      # Login to cockroach sql terminal
      cockroach_sql_env_target=$3
      $FUNCNAME env set $cockroach_sql_env_target
      if [[ $? -ne 0 ]]; then
        return 1
      fi
      option=''
      if [[ "$cockroach_sql_env_target" == "local" ]]; then
        option='--insecure'
      fi
      echo
      cockroach sql --url ${!COCKROACH_DATABASE_URL_VAR_NAME} $option
      echo
      $FUNCNAME env restore
      return 0

    elif [[ "$2" == 'init' ]]; then
      # Initialize cockroach local db
      cockroach init --insecure
      return 0

    elif [[ "$2" == 'reset' ]]; then
      # Reset cockroach local db
      $FUNCNAME env set local
      local_db_name="${COCKROACH_DATABASE_URL%%\?*}"
      local_db_name="${local_db_name##*/}"
      cockroach sql -u root --insecure --execute="DROP DATABASE IF EXISTS $local_db_name;CREATE DATABASE IF NOT EXISTS $local_db_name;SHOW DATABASES"
      $FUNCNAME env restore
      return 0

    elif [[ "$2" == 'start' ]]; then
      # Start local cockroach db instance
      node_id=26257
      node_path=~/.cockroach/node_$node_id
      if [[ ! -d "$node_path" ]]; then
        mkdir -p "$node_path"
      fi
      cockroach start \
        --insecure \
        --store=$node_path \
        --listen-addr=localhost:$node_id \
        --http-addr=localhost:8080 \
        --join=localhost:$node_id
      return 0
    fi

  elif [[ "$1" == 'postgres' ]]; then
    if [[ "$POSTGRES_DATABASE_URL_VAR_NAME" == "" ]]; then
      echo "ERROR: missing \"\$POSTGRES_DATABASE_URL_VAR_NAME\""
      return 1
    fi

    if [[ "$2" == 'sql' ]]; then
      # Login to cockroach sql terminal
      postgres_sql_env_target=$3
      $FUNCNAME env set $postgres_sql_env_target
      if [[ $? -ne 0 ]]; then
        return 1
      fi
      postgres_database_url=${!POSTGRES_DATABASE_URL_VAR_NAME}
      if [[ $postgres_database_url =~ postgresql://([^:]+):([^@]+)@([^:]+):([0-9]+)/(.+) ]]; then
        postgres_username="${BASH_REMATCH[1]}"
        postgres_password="${BASH_REMATCH[2]}"
        postgres_host="${BASH_REMATCH[3]}"
        postgres_port="${BASH_REMATCH[4]}"
        postgres_database="${BASH_REMATCH[5]}"
      else
        echo "Error: invalid PostgreSQL URL format."
        return 1
      fi
      echo
      psql -h $postgres_host -U $postgres_username -d $postgres_database -p $postgres_port
      echo
      $FUNCNAME env restore
      return 0
    fi

  elif [[ "$1" == 'inngest' ]]; then
    # Start local inngest dev server
    npx inngest-cli@latest dev
    return 0

  elif [[ "$1" == 'stripe' ]]; then
    if [[ "$STRIPE_WEBHOOK_URL" == '' ]]; then
      echo "ERROR: missing \"\$STRIPE_WEBHOOK_URL\""
      return 1
    fi

    # Start local stripe webhook listener
    echo "Have you turned off the test mode webhook on Stripe Developer Portal? [yes/no]"
    read answer
    if [[ "$answer" == 'yes' ]]; then
      stripe listen --forward-to $STRIPE_WEBHOOK_URL
    fi
    return 0

  fi

  echo "Usage: $FUNCNAME <command> <args>"
  echo
  echo "Environment Commands:"
  echo "  $FUNCNAME env get                       Get project env in the current session"
  echo "  $FUNCNAME env set <target?>             Set project env in the current session"
  echo "  $FUNCNAME env lock <target>             Lock project env for all sessions"
  echo "  $FUNCNAME env restore                   Restore env from lock file"
  echo "  $FUNCNAME env reset_vars                Reset locally cached env vars"
  echo
  echo "Credential Commands (Databag):"
  echo "  $FUNCNAME cred get <path>               Get credential value"
  echo "  $FUNCNAME cred set <path> <value>       Set credential value"
  echo
  echo "Database Commands (Prisma):"
  echo "  $FUNCNAME db view <target?>             Opens Prisma Studio to view the database"
  echo "  $FUNCNAME db pull_schema                Refresh local Prisma schema"
  echo "  $FUNCNAME db migration create <name>    Create Prisma db migrate script"
  echo "  $FUNCNAME db migration deploy <target>  Deploy migrations"
  echo
  echo "Cockroach Commands:"
  echo "  $FUNCNAME cockroach sql <target?>       Open cockroach sql terminal"
  echo "  $FUNCNAME cockroach init                Initialize cockroach local db"
  echo "  $FUNCNAME cockroach reset               Reset cockroach local db"
  echo "  $FUNCNAME cockroach start               Start local cockroach db instance"
  echo
  echo "PostgreSQL Commands:"
  echo "  $FUNCNAME postgres sql <target?>        Open postgresql terminal"
  echo
  echo "Other Service Commands:"
  echo "  $FUNCNAME inngest                       Start local inngest dev server"
  echo "  $FUNCNAME stripe                        Start local stripe webhook listener"
  echo
}
