# Где лежат инструменты тестов: $QST, если задан; иначе /opt/qs-test
# (облако, там root) или, если в /opt не записать, ~/.cache/qs-test.
# Подключают setup.sh и lib.sh
if [ -z "${QST:-}" ]; then
    QST=/opt/qs-test
    [ -d "$QST" ] || [ -w /opt ] || QST=${XDG_CACHE_HOME:-$HOME/.cache}/qs-test
fi
