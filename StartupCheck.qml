import QtQuick
import qs.Common

QtObject {
    function check(done) {
        Proc.runCommand("wallabag.depCheck",
                        ["sh", "-c", "command -v curl >/dev/null && command -v secret-tool >/dev/null"],
                        (stdout, exitCode) => {
                            if (exitCode === 0) {
                                done(null)
                                return
                            }
                            done({
                                "title": "Faltan dependencias para el plugin Wallabag",
                                "details": "Se necesitan 'curl' y 'secret-tool' (paquete libsecret) en el PATH. Instálalos y vuelve a activar el plugin."
                            })
                        })
    }
}
