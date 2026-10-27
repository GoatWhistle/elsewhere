import React from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import "./styles.css";

async function enableMocking() {
  if (!import.meta.env.DEV || import.meta.env.VITE_API_MODE === "real") return;

  const { worker } = await import("./mocks/browser");
  await worker.start({ onUnhandledRequest: "bypass" });
}

async function bootstrap() {
  await enableMocking().catch(() => undefined);

  createRoot(document.getElementById("root")!).render(
    <React.StrictMode><App /></React.StrictMode>,
  );
}

void bootstrap();
