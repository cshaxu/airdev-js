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
  if [[ "$ENV_TEMPLATE_PATH" == "" ]]; then
    echo "ERROR: missing \"\$ENV_TEMPLATE_PATH\""
    return 1
  fi
  if [[ "$COMMON_ENV_OUTPUT_PATH" == "" ]]; then
    echo "ERROR: missing \"\$COMMON_ENV_OUTPUT_PATH\""
    return 1
  fi
  if [[ "$COCKROACH_DATABASE_URL_VAR_NAME" == "" ]]; then
    echo "ERROR: missing \"\$COCKROACH_DATABASE_URL_VAR_NAME\""
    return 1
  fi

  ENV_CURRENT_VAR_NAME="${PROJECT}_ENV_CURRENT"
  ENV_PENDING_VAR_NAME="${PROJECT}_ENV_PENDING"
  COCKROACH_DATABASE_URL="${!COCKROACH_DATABASE_URL_VAR_NAME}"

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
      op whoami > /dev/null 2>&1
      if [[ $? -ne 0 ]]; then
        eval $(op signin)
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
      # apply env file of selection
      set -o allexport
      source ${!ENV_PENDING_VAR_NAME}.env
      set +o allexport
      eval "export $ENV_CURRENT_VAR_NAME=${!ENV_PENDING_VAR_NAME}"
      eval "export $ENV_PENDING_VAR_NAME="
      # clean up
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
      echo ${!ENV_CURRENT_VAR_NAME} > $LOCK_FILE
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
  elif [[ "$1" == 'db' ]]; then
    if [[ "$2" == 'sql' ]]; then
      # Login to cockroach sql terminal
      db_sql_env_target=$3
      $FUNCNAME env set $db_sql_env_target
      if [[ $? -ne 0 ]]; then
        return 1
      fi
      option=''
      if [[ "$db_sql_env_target" == "local" ]]; then
        option='--insecure'
      fi
      echo
      cockroach sql --url $COCKROACH_DATABASE_URL $option
      echo
      $FUNCNAME env restore
      return 0
    
    elif [[ "$2" == 'view' ]]; then
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
          --from-url $COCKROACH_DATABASE_URL \
          --to-schema-datamodel $PRISMA_SCHEMA_FILE \
          --script > $db_migration_create_migration_file
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
  elif [[ "$1" == 'local' ]]; then
    if [[ "$2" == 'inngest' ]]; then
      # Start local inngest dev server
      npx inngest-cli@latest dev
      return 0

    elif [[ "$2" == 'stripe' ]]; then
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

    elif [[ "$2" == 'cockroach' ]]; then
      if [[ "$3" == 'init' ]]; then
        # Initialize cockroach local db
        cockroach init --insecure
        return 0
      
      elif [[ "$3" == 'reset' ]]; then
        # Reset cockroach local db
        $FUNCNAME env set local
        local_db_name="${COCKROACH_DATABASE_URL%%\?*}"
        local_db_name="${local_db_name##*/}"
        cockroach sql -u root --insecure --execute="DROP DATABASE IF EXISTS $local_db_name;CREATE DATABASE IF NOT EXISTS $local_db_name;SHOW DATABASES"
        $FUNCNAME env restore
        return 0

      elif [[ "$3" == 'start' ]]; then
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
    fi
  fi

  echo "Usage: $FUNCNAME <command> <args>"
  echo
  echo "Env Commands:"
  echo "  $FUNCNAME env get                       Get project env in the current session"
  echo "  $FUNCNAME env set <target?>             Set project env in the current session"
  echo "  $FUNCNAME env lock <target>             Lock project env for all sessions"
  echo "  $FUNCNAME env restore                   Restore env from lock file"
  echo "  $FUNCNAME env reset_vars                Reset locally cached env vars"
  echo
  echo "Db Commands:"
  echo "  $FUNCNAME db sql <target?>              Login to cockroach sql terminal"
  echo "  $FUNCNAME db view <target?>             Opens Prisma Studio to view the database"
  echo "  $FUNCNAME db pull_schema                Refresh local Prisma schema"
  echo "  $FUNCNAME db migration create <name>    Create Prisma db migrate script"
  echo "  $FUNCNAME db migration deploy <target>  Deploy migrations"
  echo
  echo "Local Service Commands:"
  echo "  $FUNCNAME local inngest                 Start local inngest dev server"
  echo "  $FUNCNAME local stripe                  Start local stripe webhook listener"
  echo "  $FUNCNAME local cockroach init          Initialize cockroach local db"
  echo "  $FUNCNAME local cockroach reset         Reset cockroach local db"
  echo "  $FUNCNAME local cockroach start         Start local cockroach db instance"
  echo
}
