const http = require("http");
const { server: wisp } = require("@mercuryworkshop/wisp-js/server");

function attachWisp(server) {
  server.on("upgrade", (request, socket, head) => {
    const requestUrl = String(request.url || "");

    if (!requestUrl.startsWith("/wisp/")) {
      socket.destroy();
      return;
    }

    try {
      wisp.routeRequest(request, socket, head);
    } catch (error) {
      console.error("[rift-v2-wisp] upgrade failed:", error);
      socket.destroy();
    }
  });

  return server;
}

function startRiftServer(app, { port = process.env.PORT || 3000, host } = {}) {
  const server = attachWisp(http.createServer(app));
  const listenArgs = host ? [port, host] : [port];

  server.listen(...listenArgs, () => {
    const address = server.address();
    const boundPort = address && typeof address === "object" ? address.port : port;
    const displayHost = host || "localhost";
    console.log(`Rift v2 running on http://${displayHost}:${boundPort}`);
    console.log(`Wisp websocket listening on ws://${displayHost}:${boundPort}/wisp/`);
  });

  return server;
}

module.exports = {
  attachWisp,
  startRiftServer
};

