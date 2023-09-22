#!/bin/sh /etc/rc.common

EXTRA_COMMANDS="apply commit"
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
        echo "rollback failed, check /overlay/upper.dead and recover!" >&2
        exit 1
    fi
}

apply() {
    if ! rm -rf /overlay/upper.prev/ \
        || ! cp -al /overlay/upper/ /overlay/upper.prev/ \
        || ! rm -rf /overlay/upper.prev/etc/ \
        || ! cp -a /overlay/upper/etc/ /overlay/upper.prev/
    then
        echo "failed to snapshot old config"
        rm -rf /overlay/upper.prev
        exit 1
    fi

    if ! /etc/init.d/config_generation enable
    then
        echo "failed to schedule rollback"
        rm -rf /overlay/upper.prev
        exit 1
    fi

    # everything after this point may fail. if it does we'll simply roll back
    # immediately and reboot.

    trap 'reboot &' EXIT

    log() {
        printf "$LOG_FMT\n" "$*"
    }

    if ! (
        set -e

        @deploy_steps@
    )
    then
        _rollback
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
