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
                                "title": "Missing dependencies for the Wallabag plugin",
                                "details": "'curl' and 'secret-tool' (libsecret) are required on PATH. Install them and re-enable this plugin."
                            })
                        })
    }
}
