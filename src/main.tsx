import { createRoot } from "react-dom/client";
import App from "./App.tsx";
import "./index.css";
import "./lib/dummyIoT"; // Load IoT simulator for testing

createRoot(document.getElementById("root")!).render(<App />);
