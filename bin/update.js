#!/usr/bin/env node

// IMPORTS //

const cp = require("child_process");
const fs = require("fs");
const path = require("path");
const readline = require("readline");

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

const PROJECT_PATH = process.cwd();
const PACKAGE_FILE_PATH = path.join(PROJECT_PATH, "package.json");
const PACKAGE_LOCK_FILE_PATH = path.join(PROJECT_PATH, "package-lock.json");
const PACKAGE_LOCAL_FILE_PATH = path.join(PROJECT_PATH, "package-local.json");

function execute(command) {
  cp.execSync(command);
  console.log(` ✓ \`${command}\` done`);
}

async function loadFile(path) {
  const castontent = await fs.promises.readFile(path, "utf8");
  return JSON.parse(castontent);
}

async function addDeps(deps, isDev) {
  const dependenciesKey = isDev ? "devDependencies" : "dependencies";
  const packageJson = await loadFile(PACKAGE_FILE_PATH);
  const dependencies = packageJson[dependenciesKey] ?? {};
  const names = Object.keys(deps);
  const missingNames = names.filter((name) => !(name in dependencies));
  if (missingNames.length > 0) {
    missingNames.forEach((name) => {
      dependencies[name] = deps[name];
    });
    packageJson[dependenciesKey] = dependencies;
    const content = JSON.stringify(packageJson, null, 2) + "\n";
    await fs.promises.writeFile(PACKAGE_FILE_PATH, content);
    console.log(" ✓ `package.json` updated");
  }
  names
    .map((name) => `npm install${isDev ? " --save-dev" : ""} ${name}`)
    .forEach(execute);
}

async function update() {
  const { dependencies, devDependencies } = await loadFile(PACKAGE_FILE_PATH);
  const newDeps = dependencies ?? {};
  const newDevDeps = devDependencies ?? {};
  let addedDeps = {};
  let addedDevDeps = {};

  if (fs.existsSync(PACKAGE_LOCAL_FILE_PATH)) {
    const { dependencies: oldDepsRaw, devDependencies: oldDevDepsRaw } =
      await loadFile(PACKAGE_LOCAL_FILE_PATH);
    const oldDeps = oldDepsRaw ?? {};
    const oldDevDeps = oldDevDepsRaw ?? {};

    // remove dependencies
    const removedDepNames = Object.keys(oldDeps).filter(
      (name) => !(name in newDeps) || newDeps[name] !== oldDeps[name]
    );
    const removedDevDepNames = Object.keys(oldDevDeps).filter(
      (name) => !(name in newDevDeps) || newDevDeps[name] !== oldDevDeps[name]
    );
    removedDepNames.map((name) => `npm uninstall ${name}`).forEach(execute);
    removedDevDepNames.map((name) => `npm uninstall ${name}`).forEach(execute);

    // add dependencies
    addedDeps = Object.keys(newDeps)
      .filter((name) => !(name in oldDeps) || newDeps[name] !== oldDeps[name])
      .reduce((acc, name) => {
        acc[name] = newDeps[name];
        return acc;
      }, {});
    addedDevDeps = Object.keys(newDevDeps)
      .filter(
        (name) => !(name in oldDevDeps) || newDevDeps[name] !== oldDevDeps[name]
      )
      .reduce((acc, name) => {
        acc[name] = newDevDeps[name];
        return acc;
      }, {});
  } else {
    const githubDepNames = Object.keys(newDeps).filter((name) =>
      newDeps[name].startsWith("github:")
    );
    const githubDevDepNames = Object.keys(newDevDeps).filter((name) =>
      newDevDeps[name].startsWith("github:")
    );
    githubDepNames.map((name) => `npm uninstall ${name}`).forEach(execute);
    githubDevDepNames.map((name) => `npm uninstall ${name}`).forEach(execute);

    addedDeps = githubDepNames.reduce((acc, name) => {
      acc[name] = newDeps[name];
      return acc;
    }, {});
    addedDevDeps = githubDevDepNames.reduce((acc, name) => {
      acc[name] = newDevDeps[name];
      return acc;
    }, {});
  }
  await addDeps(addedDeps, false);
  await addDeps(addedDevDeps, true);
}

async function main() {
  if (!fs.existsSync(PACKAGE_FILE_PATH)) {
    console.log(` × "${PACKAGE_FILE_PATH}" missing`);
    return;
  }
  if (fs.existsSync(PACKAGE_LOCK_FILE_PATH)) {
    await update();
  }
  execute("npm install");
  cp.execSync(`cp ${PACKAGE_FILE_PATH} ${PACKAGE_LOCAL_FILE_PATH}`);
}

main()
  .catch((error) => console.error(error))
  .finally(() => rl.close());
