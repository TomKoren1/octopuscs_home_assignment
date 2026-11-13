// Runs automatically the FIRST time the MongoDB container starts
// (i.e. only when the data volume is empty). The official mongo image
// executes every *.js / *.sh file in /docker-entrypoint-initdb.d/.
//
// `db` already points at the database named in MONGO_INITDB_DATABASE.

db.fruits.insertMany([
  { _id: 1, name: "apples",   qty: 5, rating: 3 },
  { _id: 2, name: "bananas",  qty: 7, rating: 1, microsieverts: 0.1 },
  { _id: 3, name: "oranges",  qty: 6, rating: 2 },
  { _id: 4, name: "avocados", qty: 3, rating: 5 },
]);

print(`Seeded ${db.fruits.countDocuments()} fruits into "${db.getName()}"`);
