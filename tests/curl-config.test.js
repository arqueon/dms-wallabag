const assert = require("node:assert/strict")
const fs = require("node:fs")
const http = require("node:http")
const path = require("node:path")
const { spawn } = require("node:child_process")
const vm = require("node:vm")

const helpers = vm.createContext({})
vm.runInContext(fs.readFileSync(path.join(__dirname, "../JS/wallabag.js"), "utf8"), helpers)

async function main() {
    const server = http.createServer((request, response) => {
        let body = ""
        request.setEncoding("utf8")
        request.on("data", chunk => body += chunk)
        request.on("end", () => {
            assert.equal(request.headers.authorization, "Bearer fake.token/+=")
            assert.equal(new URLSearchParams(body).get("password"), "a b&c\"'\\")
            assert.equal(new URLSearchParams(body).get("client_secret"), "fake-client-secret")
            response.end("ok")
        })
    })
    await new Promise(resolve => server.listen(0, "127.0.0.1", resolve))
    try {
        const argv = ["-sS", "-K", "-", "-X", "POST", `http://127.0.0.1:${server.address().port}/token`]
        const config = helpers.curlConfig({ password: "a b&c\"'\\", client_secret: "fake-client-secret" }, "fake.token/+=")
        assert(!argv.join(" ").includes("fake.token"))
        assert(!argv.join(" ").includes("fake-client-secret"))
        assert.throws(() => helpers.curlConfig(null, "bad\ntoken"))
        const result = await new Promise((resolve, reject) => {
            const process = spawn("curl", argv)
            let output = ""
            process.stdout.on("data", chunk => output += chunk)
            process.on("error", reject)
            process.on("close", code => resolve({ code, output }))
            process.stdin.end(config)
        })
        assert.equal(result.code, 0)
        assert.equal(result.output, "ok")
    } finally {
        await new Promise(resolve => server.close(resolve))
    }
}

main().catch(error => {
    console.error(error)
    process.exitCode = 1
})
