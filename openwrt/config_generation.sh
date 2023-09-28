#!/bin/sh /etc/rc.common

EXTRA_COMMANDS="apply_reboot prepare_reload apply_reload commit"
START=99

_unregister_script() {
    /etc/init.d/config_generation disable
    rm /etc/init.d/config_generation
}

_rollback() {
    rm -rf /overlay/upper.dead
    mv /overlay/upper /overlay/upper.dead
    # this should never fail, unless something *else* is also mucking
    # with overlayfs state.
    if mv -T /overlay/upper.prev /overlay/upper; then
        rm -rf /overlay/upper.dead
    else
        echo "rollback failed, manual recovery needed. check /overlay/upper.dead!" >&2
        exit 1
    fi
}

_prepare_apply() {
    CYAN='\e[36m'
    RED='\e[31m'
    NORMAL='\e[0m'

    log() {
        printf "$CYAN>> %s$NORMAL\n" "$*"
    }

    log_err() {
        printf "$RED>> %s$NORMAL\n" "$*"
    }

    if [ -e /overlay/upper.dead ]; then
        log_err "previous failed deployment still needs recovery"
        exit 1
    fi

    if ! rm -rf /overlay/upper.prev/ \
        || ! cp -al /overlay/upper/ /overlay/upper.prev/ \
        || ! rm -rf /overlay/upper.prev/etc/ \
        || ! cp -a /overlay/upper/etc/ /overlay/upper.prev/
    then
        log_err "failed to snapshot old config"
        rm -rf /overlay/upper.prev
        exit 1
    fi

    if ! /etc/init.d/config_generation enable
    then
        log_err "failed to schedule rollback"
        rm -rf /overlay/upper.prev
        exit 1
    fi
}

_run_steps() {
    (
        set -e
        @deploy_steps@
    )
}

apply_reboot() {
    _prepare_apply

    # everything after this point may fail. if it does we'll simply roll back
    # immediately and reboot.

    trap 'reboot &' EXIT

    if ! _run_steps; then
        log_err 'deployment failed, rolling back and rebooting ...'
        _rollback
        exit 1
    fi

    log 'rebooting device ...'
}

prepare_reload() {
    mkdir /overlay/upper.prev
    /etc/init.d/config_generation enable
}

apply_reload() {
    _prepare_apply

    # everything after this point may fail. if it does we'll simply roll back
    # immediately and reboot.

    trap 'reboot &' EXIT

    if _run_steps; then
        trap '' EXIT
        log 'reloading config ...'
        reload_config
        # give service restarts a chance
        log 'waiting @reload_service_wait@s for services ...'
        sleep @reload_service_wait@
        exit 0
    else
        log_err 'deployment failed, rolling back and rebooting ...'
        _rollback
        exit 1
    fi
}

commit() {
    if ! [ -e /overlay/upper.prev ]; then
        exit 1
    fi
    touch /tmp/.abort-rollback
}

start() {
    [ -d /overlay/upper.prev ] || {
        _unregister_script
        exit 0
    }

    local needs_rollback=true
    local timeout=@rollback_timeout@

    while [ $timeout -gt 0 ]; do
        timeout=$(( timeout - 1 ))
        [ -e /tmp/.abort-rollback ] && {
            needs_rollback=false
            rm /tmp/.abort-rollback
            break
        }
        sleep 1
    done

    if $needs_rollback; then
        _rollback
        _unregister_script
        reboot
    else
        rm -rf /overlay/upper.prev
        _unregister_script
    fi
}
