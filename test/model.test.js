// Run: node --test test/model.test.js
// Model.js is a QML ".pragma library" file; strip the pragma and load it as a
// plain script so its functions can be called from node.
const { test } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const src = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
  .replace(/^\.pragma library\s*$/m, "")
const Model = {}
vm.runInNewContext(src, Model)

const wifi = { name: "Home", uuid: "w", type: "802-11-wireless", device: "wlan0", active: true }
const lanDns = { link: "wlan0", server: "192.168.1.1", defaultRoute: false, domains: ["home.example"] }

function vpn(fullTunnel) {
  return { name: "wg0", uuid: "v", type: "wireguard", device: "wg0", active: true, fullTunnel }
}

test("full tunnel holding ~. with LAN split DNS: no leak, split DNS listed", () => {
  const state = { profiles: [wifi, vpn(true)], dns: [
    lanDns,
    { link: "wg0", server: "10.64.0.1", defaultRoute: true, domains: [] },
  ] }
  assert.equal(Model.dnsLeaks(state), false)
  assert.deepEqual(Model.splitDns(state).map(l => l.link), ["wlan0"])
})

test("full tunnel while Wi-Fi still answers catch-all queries: leak", () => {
  const state = { profiles: [wifi, vpn(true)], dns: [
    { link: "wlan0", server: "192.168.1.1", defaultRoute: true, domains: [] },
    { link: "wg0", server: "10.64.0.1", defaultRoute: true, domains: [] },
  ] }
  assert.equal(Model.dnsLeaks(state), true)
})

test("split tunnel with general DNS on Wi-Fi: not a leak", () => {
  const state = { profiles: [wifi, vpn(false)], dns: [
    { link: "wlan0", server: "192.168.1.1", defaultRoute: true, domains: [] },
    { link: "wg0", server: "10.0.0.1", defaultRoute: false, domains: ["home.arpa"] },
  ] }
  assert.equal(Model.dnsLeaks(state), false)
  assert.doesNotMatch(Model.summary(state), /DNS outside VPN/)
})

test("default-route link with no server can't leak", () => {
  const state = { profiles: [wifi, vpn(true)], dns: [
    { link: "wlan0", server: "", defaultRoute: true, domains: [] },
  ] }
  assert.equal(Model.dnsLeaks(state), false)
})
