#!/bin/sh
# Wi-Fi backend for the bar's Wi-Fi panel. Talks to NetworkManager via nmcli.
#   wifi.sh status                 -> STATE|state|ssid|ip|iface     (state COMPLETED = connected)
#   wifi.sh scan                   -> NET|dBm|sec|saved_id|current|ssid   (strongest first)
#                                     sec: 0 open, 1 password (PSK/SAE), 2 enterprise (802.1X)
#   wifi.sh connect SSID [-]       -> OK|ip|note   or  FAIL|reason
#                                  "-" = read the Wi-Fi password from stdin
#   wifi.sh connect-eap SSID IDENTITY [SERVER_DOMAIN]     (password read from stdin)
#                                  WPA2-Enterprise (eduroam etc): PEAP + MSCHAPv2.
#                                  SERVER_DOMAIN defaults to the part after @ in IDENTITY.
#   wifi.sh forget SSID            -> FORGOT|profiles_removed|note   or  FAIL|reason
#   wifi.sh disconnect|reconnect   -> OK|
# Any command may print ERR|reason instead (e.g. NetworkManager isn't running).
# Saved networks are NetworkManager's connection profiles, so nmcli/nmtui and
# this panel see the same list.
#
# NixOS: networking.networkmanager.enable = true, and your user in the
# "networkmanager" group (NixOS's polkit rule lets that group do all of this).
#
# Secrets never appear in any process's arguments (which `ps` shows to every user):
# they arrive on stdin and reach NetworkManager through nmcli's passwd-file, read
# from /dev/stdin, using only shell builtins on the way. NetworkManager saves them
# in the profile (/etc/NetworkManager/system-connections, root-only).
# Override the interface with WIFI_IF.

export LC_ALL=C.UTF-8   # nmcli's messages and yes/no columns are parsed below

command -v nmcli >/dev/null 2>&1 || { echo "ERR|nmcli not found: is NetworkManager enabled?"; exit 0; }
[ "$(nmcli -t -f RUNNING general 2>/dev/null)" = running ] ||
    { echo "ERR|NetworkManager isn't running"; exit 0; }

IF=${WIFI_IF:-$(nmcli -t -f DEVICE,TYPE device 2>/dev/null | awk -F: '$2 == "wifi" {print $1; exit}')}
[ -n "$IF" ] || { echo "ERR|no Wi-Fi device (is the radio blocked? try: nmcli radio wifi on)"; exit 0; }

# With -e no, nmcli doesn't escape colons; every list below puts the SSID last,
# so everything after the last fixed field is the SSID, colons and all.

ipaddr() { ip -4 -o addr show dev "$IF" 2>/dev/null | awk '{split($4, a, "/"); print a[1]; exit}'; }

cur_ssid() {
    nmcli -e no -t -f ACTIVE,SSID device wifi list ifname "$IF" --rescan no 2>/dev/null |
        sed -n 's/^yes://p' | head -n 1
}

# "uuid<TAB>ssid" for every saved Wi-Fi profile.
profiles() {
    nmcli -t -f UUID,TYPE connection show 2>/dev/null | while IFS=: read -r u t; do
        [ "$t" = 802-11-wireless ] || continue
        printf '%s\t%s\n' "$u" "$(nmcli -e no -g 802-11-wireless.ssid connection show uuid "$u" 2>/dev/null)"
    done
}
uuids_for() { profiles | awk -F '\t' -v s="$1" '$2 == s {print $1}'; }

# WPA3-only networks need SAE; everything else with a password is wpa-psk.
keymgmt() {
    _sec=$(nmcli -e no -t -f SECURITY,SSID device wifi list ifname "$IF" --rescan no 2>/dev/null |
        awk -v s="$1" '{i = index($0, ":")} substr($0, i + 1) == s {print substr($0, 1, i - 1); exit}')
    case $_sec in
        *WPA1*|*WPA2*) echo wpa-psk ;;
        *WPA3*)        echo sae ;;
        *)             echo wpa-psk ;;
    esac
}

# passwd-file values take backslash escapes and lose unescaped edge whitespace,
# so escape \ and every space/tab. Builtins only: the secret never leaves the shell.
esc() {
    _in=$1 _out=
    while [ -n "$_in" ]; do
        _rest=${_in#?}
        _c=${_in%"$_rest"}
        _in=$_rest
        case $_c in
            \\)  _out="$_out\\\\" ;;
            ' ') _out="$_out\\ " ;;
            '	') _out="$_out\\t" ;;
            *)   _out="$_out$_c" ;;
        esac
    done
    printf '%s' "$_out"
}

# add_profile SSID [setting value]... -> NEWUUID. Autoconnect stays off until it
# has connected once, so NetworkManager doesn't race us to it without the secret.
NEWUUID=
add_profile() {
    _ssid=$1; shift
    _o=$(nmcli connection add type wifi ifname "$IF" con-name "$_ssid" ssid "$_ssid" \
        connection.autoconnect no "$@" 2>&1)
    NEWUUID=$(printf '%s\n' "$_o" | sed -n 's/.*(\([0-9a-f-]\{36\}\)) successfully added.*/\1/p')
    [ -n "$NEWUUID" ] && return 0
    echo "FAIL|couldn't save the network: $(why "$_o")"
    return 1
}

# Turn nmcli's error output into a short reason.
why() {
    case $1 in
        *"Secrets were required"*|*"no-secrets"*) echo "wrong password, or login rejected" ;;
        *"Timeout expired"*)                     echo "timed out joining" ;;
        *[Nn]"ot authorized"*)                   echo "not allowed: add yourself to the networkmanager group" ;;
        *) printf '%s\n' "$1" | sed -n 's/^Error: \(Connection activation failed: \)\{0,1\}//p' | head -n 1 ;;
    esac
}

# up UUID [SECRET_PROPERTY]: activate, handing over $pass as that property.
UPERR=
up() {
    if [ -n "$2" ]; then
        _o=$(printf '%s:%s\n' "$2" "$(esc "$pass")" |
            nmcli --wait 40 connection up uuid "$1" ifname "$IF" passwd-file /dev/stdin 2>&1)
    else
        _o=$(nmcli --wait 40 connection up uuid "$1" ifname "$IF" 2>&1)
    fi
    _rc=$?
    [ $_rc -eq 0 ] && return 0
    UPERR=$(why "$_o")
    [ -n "$UPERR" ] || UPERR="couldn't join (nmcli exit $_rc)"
    return 1
}

# A new profile connected: keep it (autoconnect on) and drop the ones it replaces.
keep() {
    nmcli connection modify uuid "$1" connection.autoconnect yes >/dev/null 2>&1
    shift
    for _u in "$@"; do nmcli connection delete uuid "$_u" >/dev/null 2>&1; done
}

case "$1" in
status)
    st=$(nmcli -t -f GENERAL.STATE,IP4.ADDRESS device show "$IF" 2>/dev/null)
    code=$(printf '%s\n' "$st" | sed -n 's/^GENERAL\.STATE:\([0-9]*\).*/\1/p')
    if [ "$code" = 100 ]; then
        state=COMPLETED
    else
        state=$(printf '%s\n' "$st" | sed -n 's/^GENERAL\.STATE:[0-9]* (\(.*\))$/\1/p')
    fi
    printf 'STATE|%s|%s|%s|%s\n' "$state" "$(cur_ssid)" \
        "$(printf '%s\n' "$st" | sed -n 's/^IP4\.ADDRESS\[1\]:\([0-9.]*\).*/\1/p')" "$IF"
    ;;

scan)
    f=IN-USE,SIGNAL,SECURITY,SSID
    out=$(nmcli -e no -t -f $f device wifi list ifname "$IF" --rescan yes 2>/dev/null) ||
        out=$(nmcli -e no -t -f $f device wifi list ifname "$IF" --rescan no 2>/dev/null)
    # Exported: an assignment written before a pipeline only reaches its FIRST command.
    KNOWN=$(profiles | cut -f 2)
    export KNOWN
    # SIGNAL is NetworkManager's 0-100, which it maps linearly from -100..-40 dBm;
    # map it back so the panel's dBm thresholds mean what they did.
    printf '%s\n' "$out" | awk '
        BEGIN {
            n = split(ENVIRON["KNOWN"], kl, "\n")
            for (i = 1; i <= n; i++) if (kl[i] != "" && !(kl[i] in id)) id[kl[i]] = i - 1
        }
        {
            l = $0
            i = index(l, ":"); use = substr(l, 1, i - 1); l = substr(l, i + 1)
            i = index(l, ":"); q = substr(l, 1, i - 1) + 0; l = substr(l, i + 1)
            i = index(l, ":"); sf = substr(l, 1, i - 1); s = substr(l, i + 1)
            if (s == "" || s == "--") next              # hidden networks
            dbm = int(q * 0.6) - 100
            if (!(s in best) || dbm > best[s]) {       # keep the strongest AP per SSID
                best[s] = dbm
                sec[s] = (sf ~ /802\.1X/) ? 2 : (sf ~ /WPA|WEP|SAE/) ? 1 : 0
            }
            if (use == "*") cur[s] = 1
        }
        END {
            for (s in best)
                printf "NET|%d|%d|%s|%d|%s\n", best[s], sec[s], (s in id) ? id[s] : -1, (s in cur), s
        }' | sort -t '|' -k2,2 -nr
    ;;

connect)
    ssid=$2 pass= note=
    if [ "$3" = - ]; then
        IFS= read -r pass || :
        [ ${#pass} -ge 8 ] && [ ${#pass} -le 64 ] || { echo "FAIL|password must be 8-63 characters"; exit 0; }
    fi
    old=$(uuids_for "$ssid")
    if [ -n "$old" ] && [ -z "$pass" ]; then          # saved: just bring it up
        set -- $old
        if up "$1"; then echo "OK|$(ipaddr)|"; else echo "FAIL|$UPERR"; fi
        exit 0
    fi
    if [ -n "$pass" ]; then
        add_profile "$ssid" wifi-sec.key-mgmt "$(keymgmt "$ssid")" || exit 0
        key=802-11-wireless-security.psk
    else
        add_profile "$ssid" || exit 0
        key=
    fi
    if up "$NEWUUID" $key; then
        keep "$NEWUUID" $old                          # a new password replaces the old profile
        echo "OK|$(ipaddr)|$note"
    else
        nmcli connection delete uuid "$NEWUUID" >/dev/null 2>&1
        echo "FAIL|$UPERR"
    fi
    ;;

connect-eap)
    ssid=$2 ident=$3 domain=$4 note=
    IFS= read -r pass || :
    [ -n "$ident" ] && [ -n "$pass" ] || { echo "FAIL|username and password are both required"; exit 0; }
    old=$(uuids_for "$ssid")      # kept until the new credentials actually work
    realm=${ident#*@}; [ "$realm" = "$ident" ] && realm=
    [ -n "$domain" ] || domain=$realm       # you@ucla.edu -> verify the server is *.ucla.edu
    # PEAPv0 with TLS 1.3 off: many campus RADIUS servers break on PEAP over TLS 1.3.
    set -- wifi-sec.key-mgmt wpa-eap wifi-sec.pmf disable \
        802-1x.eap peap 802-1x.phase2-auth mschapv2 \
        802-1x.phase1-peapver 0 802-1x.phase1-auth-flags tls-1-3-disable \
        802-1x.identity "$ident"
    # hides your username outside the tunnel
    [ -n "$realm" ] && set -- "$@" 802-1x.anonymous-identity "@$realm"
    if [ -n "$domain" ]; then
        set -- "$@" 802-1x.domain-suffix-match "$domain"
    else
        note="server not verified"
    fi
    add_profile "$ssid" "$@" || exit 0
    if up "$NEWUUID" 802-1x.password; then
        pass=
        keep "$NEWUUID" $old
        echo "OK|$(ipaddr)|$note"
    else
        pass=
        nmcli connection delete uuid "$NEWUUID" >/dev/null 2>&1
        case $UPERR in wrong*) UPERR="login rejected" ;; esac
        echo "FAIL|$UPERR"
    fi
    ;;

forget)
    # Remove EVERY profile for this name (duplicates would keep it "saved").
    ids=$(uuids_for "$2")
    [ -n "$ids" ] || { echo "FAIL|$2 isn't saved"; exit 0; }
    n=0 bad=0
    for u in $ids; do
        if nmcli connection delete uuid "$u" >/dev/null 2>&1; then n=$((n + 1)); else bad=1; fi
    done
    [ $n -gt 0 ] || { echo "FAIL|couldn't remove $2 (not in the networkmanager group?)"; exit 0; }
    note=
    [ $bad = 1 ] && note="some copies couldn't be removed"
    echo "FORGOT|$n|$note"
    ;;

disconnect) nmcli device disconnect "$IF" >/dev/null 2>&1; echo "OK|" ;;
reconnect)  nmcli device connect "$IF"    >/dev/null 2>&1; echo "OK|" ;;
*)          echo "ERR|unknown command: $1" ;;
esac
