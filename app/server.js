const os = require("os");
const express = require("express");
const { MongoClient } = require("mongodb");

// --- Configuration: everything comes from environment variables ------------
const PORT = process.env.PORT || 3000;
const MONGO_URL = process.env.MONGO_URL || "mongodb://mongo:27017";
const MONGO_DB = process.env.MONGO_DB || "store";
// Which build is running: CI bakes the git commit SHA into the image.
const APP_VERSION = process.env.APP_VERSION || "dev";

// One client for the whole process. It keeps a connection pool and
// reconnects by itself, so we never open a connection per request.
const client = new MongoClient(MONGO_URL, {
  serverSelectionTimeoutMS: 3000,
  // Credentials are passed separately (not inside the URL), so special
  // characters in the password never need URL-encoding.
  auth: process.env.MONGO_USER
    ? { username: process.env.MONGO_USER, password: process.env.MONGO_PASSWORD }
    : undefined,
});
const fruits = client.db(MONGO_DB).collection("fruits");

const app = express();

const SEED_APPLES = 5;   // the value from the seed script, used by "Reset"
const MAX_EMOJIS = 50;   // cap so a big number doesn't flood the page

// The page: "Hello World" + the number of apples, read live from the DB.
app.get("/", async (req, res) => {
  try {
    const apples = await fruits.findOne({ name: "apples" });
    const qty = apples ? apples.qty : 0;
    const emojis = "🍎".repeat(Math.min(qty, MAX_EMOJIS)) + (qty > MAX_EMOJIS ? " …" : "");
    res.send(`<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Hello Apples</title>
    <style>
      body   { font-family: sans-serif; text-align: center; margin: 12vh 16px 0; }
      .basket { font-size: 2.2rem; max-width: 640px; margin: 0 auto 1.5rem; word-wrap: break-word; }
      form   { display: inline; }
      button { font-size: 1rem; padding: .6rem 1.2rem; margin: .25rem; border-radius: 8px;
               border: 1px solid #aaa; background: #fff; cursor: pointer; }
      button.primary { background: #d62828; border-color: #d62828; color: #fff; }
      small  { display: block; margin-top: 2rem; color: #666; }
    </style>
  </head>
  <body>
    <h1>Hello World!</h1>
    <p>We have <strong id="apples">${qty}</strong> apples in the database.</p>
    <div class="basket" aria-hidden="true">${emojis}</div>
    <form method="post" action="/apples"><button class="primary">Add an apple 🍎</button></form>
    <form method="post" action="/apples/reset"><button>Reset to ${SEED_APPLES}</button></form>
    <small>Served by container: ${os.hostname()} · version: ${APP_VERSION.slice(0, 7)}</small>
  </body>
</html>`);
  } catch (err) {
    console.error("DB query failed:", err.message);
    res.status(503).send("Database unavailable");
  }
});

// Buttons. Both use the Post/Redirect/Get pattern: change the DB, then
// redirect (303) back to "/", so refreshing the page never re-submits.
app.post("/apples", async (req, res) => {
  try {
    // $inc is atomic in MongoDB: two replicas clicking at once never lose a count
    await fruits.updateOne({ name: "apples" }, { $inc: { qty: 1 } });
    res.redirect(303, "/");
  } catch (err) {
    console.error("DB update failed:", err.message);
    res.status(503).send("Database unavailable");
  }
});

app.post("/apples/reset", async (req, res) => {
  try {
    await fruits.updateOne({ name: "apples" }, { $set: { qty: SEED_APPLES } });
    res.redirect(303, "/");
  } catch (err) {
    console.error("DB update failed:", err.message);
    res.status(503).send("Database unavailable");
  }
});

// Health endpoint: used by Docker / the load balancer to know if we are OK.
app.get("/health", async (req, res) => {
  try {
    await client.db("admin").command({ ping: 1 });
    res.json({ status: "ok", version: APP_VERSION });
  } catch (err) {
    res.status(503).json({ status: "error", message: err.message });
  }
});

const server = app.listen(PORT, () => {
  console.log(`Listening on port ${PORT}, database ${MONGO_URL}/${MONGO_DB}`);
});

// Graceful shutdown: `docker stop` sends SIGTERM. Finish in-flight requests,
// close the DB connection, then exit - instead of being killed after 10s.
function shutdown(signal) {
  console.log(`${signal} received, shutting down`);
  server.close(async () => {
    await client.close();
    process.exit(0);
  });
}
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
