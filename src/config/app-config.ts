import packageJson from "../../package.json";

const currentYear = new Date().getFullYear();

export const APP_CONFIG = {
  name: "League Admin",
  url: "https://league-admin.local",
  repository: "https://github.com/wamwagii/league-admin",
  version: packageJson.version,
  copyright: `© ${currentYear}, League Admin.`,
  meta: {
    title: "League Admin",
    description: "Admin panel for multi-competition football league management.",
  },
};
