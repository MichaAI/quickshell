import MichaAI.Logind as L

// Обёртка над элементом плагина: Logind грузит её через
// Qt.createComponent — без плагина (чужая сборка quickshell) шелл не падает
L.Logind {}
