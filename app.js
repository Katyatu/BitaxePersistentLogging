"use strict";

const express = require("express");
const { exec } = require("child_process");
const { spawn } = require("child_process");
const path = require("path");
const fs = require("fs").promises;

let config;
try {
  config = Object.freeze(require("./config.json"));
} catch (error) {
  console.error("Error loading config.json:", error.message);
  process.exit(1);
}

const app = express();
const PORT = config.serverPort;
const HOST = config.serverLocalIP;
const SNAPSHOT_SCRIPT_PATH = path.join(__dirname, "BPL-Snapshot.sh");
const SNAPSHOT_PNG_PATH = path.join("/tmp/BPL/BPL-Snapshot.png");
const LOGGING_SCRIPT_PATH = path.join(__dirname, "BPL-Logging.sh");

// Start logging script as a detached process
const loggingScript = spawn("bash", [LOGGING_SCRIPT_PATH], {
  detached: true,
  stdio: ["ignore", "ignore", "ignore"],
});
loggingScript.unref();

// Handle server shutdown to terminate logging script
process.on("SIGINT", () => {
  loggingScript.kill("SIGTERM");
  process.exit();
});

app.get("/", async (req, res) => {
  try {
    // Execute snapshot script
    await new Promise((resolve, reject) => {
      exec(`bash ${SNAPSHOT_SCRIPT_PATH}`, (error, stdout, stderr) => {
        if (error) {
          console.error(`Script error: ${error.message}\nStderr: ${stderr}`);
          return reject(new Error("Script execution failed"));
        }
        resolve();
      });
    });

    // Check if PNG file exists
    await fs.access(SNAPSHOT_PNG_PATH);

    // Send the PNG file as response
    res.set("Content-Type", "image/png");
    res.sendFile(SNAPSHOT_PNG_PATH, (err) => {
      if (err) {
        console.error(`Error sending file: ${err.message}`);
        res.status(500).send("Error sending PNG file");
      }
    });
  } catch (error) {
    console.error(`Error: ${error.message}`);
    res.status(500).send("Server error: Failed to generate or retrieve PNG");
  }
});

// Start server
app.listen(PORT, HOST, () => {
  console.log(`Server running at http://${HOST}:${PORT}/`);
});
