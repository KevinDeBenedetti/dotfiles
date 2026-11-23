// Puts every open issue of the given repositories on the board, in the column
// of its labels: for issues opened before the App was installed. Reads the
// board from wrangler.toml, and uses your own token:
//
//   GH_TOKEN="$(gh auth token)" node .github/project-board/backfill.mjs owner/repo...
//
// The token needs the `project` and `repo` scopes. Running it again is safe:
// an issue already in its column is left as it is.
import { readFileSync } from "node:fs";
import { backfill } from "./board.mjs";
import { client } from "./github.mjs";

const toml = readFileSync(new URL("./wrangler.toml", import.meta.url), "utf8");
const variable = (name) => new RegExp(`^${name} = "([^"]*)"$`, "m").exec(toml)?.[1];
const env = {
  PROJECT_OWNER: variable("PROJECT_OWNER"),
  PROJECT_NUMBER: variable("PROJECT_NUMBER"),
};

for (const [name, value] of Object.entries(env)) {
  if (!value) {
    console.error(`${name} is missing from the [vars] of wrangler.toml`);
    process.exit(1);
  }
}

const repositories = process.argv.slice(2);
if (!process.env.GH_TOKEN || !repositories.length) {
  console.error('Usage: GH_TOKEN="$(gh auth token)" node backfill.mjs owner/repo...');
  process.exit(2);
}
await backfill(client(process.env.GH_TOKEN), env, repositories, (line) => console.log(line));
