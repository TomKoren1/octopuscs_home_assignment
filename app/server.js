const os = require("os");
const express = require("express");
const { MongoClient } = require("mongodb");

const PORT = process.env.PORT || 3000;
const MONGO_URL = process.env.MONGO_URL || "mongodb://mongo:27017";
const MONGO_DB = process.env.MONGO_DB || "store";
const APP_VERSION = process.env.APP_VERSION || "dev";

// One shared client: it pools connections and reconnects by itself
const client = new MongoClient(MONGO_URL, {
  serverSelectionTimeoutMS: 3000,
  // Not in the URL, so the password never needs URL-encoding
  auth: process.env.MONGO_USER
    ? { username: process.env.MONGO_USER, password: process.env.MONGO_PASSWORD }
    : undefined,
});
const fruits = client.db(MONGO_DB).collection("fruits");

const app = express();

const SEED_APPLES = 5; // same as mongo/init/01-seed.js
const MAX_EMOJIS = 50;

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

// Post/Redirect/Get: refreshing the page never re-submits the form
app.post("/apples", async (req, res) => {
  try {
    // $inc is atomic: concurrent clicks on different replicas are never lost
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

// `docker stop` sends SIGTERM: finish in-flight requests, then exit
function shutdown(signal) {
  console.log(`${signal} received, shutting down`);
  server.close(async () => {
    await client.close();
    process.exit(0);
  });
}
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
