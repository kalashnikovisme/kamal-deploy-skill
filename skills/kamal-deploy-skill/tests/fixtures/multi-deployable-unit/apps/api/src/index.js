const express = require("express");
const { formatResponse } = require("@fixture/shared-utils");

const app = express();
const port = process.env.PORT || 3001;

app.get("/health", (req, res) => {
  res.json(formatResponse({ status: "ok" }));
});

app.listen(port, () => {
  console.log(`api listening on port ${port}`);
});
