const profile = document.getElementById("profile");
const install = document.getElementById("install");
const baseCommand = install.textContent;
function syncProfile() {
  install.textContent = baseCommand + profile.value;
  document.getElementById("hint").textContent = profile.value
    ? "Pełny OQLLM dodaje API OQL na porcie 11440. Przed instalacją zaloguj gh na konto z dostępem do prywatnego oqllm/oqllm."
    : "Publiczny SubLLM. Instalacja pobiera modele i włącza usługi systemd.";
}
profile.addEventListener("change", syncProfile);
syncProfile();
for (const button of document.querySelectorAll("[data-copy]")) {
  const original = button.textContent;
  let timer;
  button.addEventListener("click", async () => {
    clearTimeout(timer);
    const code = document.getElementById(button.dataset.copy);
    try {
      await navigator.clipboard.writeText(code.textContent);
      button.textContent = "Skopiowano";
      document.getElementById("status").textContent = "Skopiowano polecenie.";
    } catch {
      const selection = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents(code);
      selection.removeAllRanges();
      selection.addRange(range);
      button.textContent = "Użyj Ctrl+C";
      document.getElementById("status").textContent = "Polecenie zaznaczone. Skopiuj je skrótem klawiaturowym.";
    }
    timer = setTimeout(() => { button.textContent = original; }, 2200);
  });
}
