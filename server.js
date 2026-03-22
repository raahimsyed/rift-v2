const app = require("./server/app");
const { startRiftServer } = require("./server/start-server");

const PORT = process.env.PORT || 3000;

if (require.main === module) {
  startRiftServer(app, { port: PORT });
}

module.exports = app;

