const express = require("express");
const path = require("path");

const app = express();
const root = path.join(__dirname, "..");

app.disable("x-powered-by");

app.get("/wisp/", (_req, res) => {
  res.status(426);
  res.setHeader("Upgrade", "websocket");
  res.setHeader("Connection", "Upgrade");
  res.type("text/plain").send("Wisp websocket endpoint is available at this path via websocket upgrade.");
});

app.use(express.static(root, {
  extensions: ["html"],
  redirect: false
}));

app.get("*", (_req, res) => {
  res.sendFile(path.join(root, "index.html"));
});

module.exports = app;

