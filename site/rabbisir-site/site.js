const languageStorageKey = "rabbisir-language";
const languageSwitch = document.querySelector(".language-switch");
const wechatButton = document.querySelector(".wechat-profile-button");
const wechatDialog = document.querySelector(".wechat-dialog");
const wechatDialogClose = document.querySelector(".wechat-dialog-close");

function savedLanguage() {
  try {
    return localStorage.getItem(languageStorageKey) === "zh" ? "zh" : "en";
  } catch {
    return "en";
  }
}

function applyLanguage(language) {
  document.documentElement.lang = language === "zh" ? "zh-CN" : "en";

  document.querySelectorAll("[data-en][data-zh]").forEach((element) => {
    element.textContent = element.dataset[language];
  });

  document.querySelectorAll("[data-aria-en][data-aria-zh]").forEach((element) => {
    element.setAttribute("aria-label", element.dataset[`aria${language === "zh" ? "Zh" : "En"}`]);
  });

  languageSwitch.textContent = language === "zh" ? "EN" : "中文";
  languageSwitch.setAttribute("aria-label", language === "zh" ? "Switch to English" : "Switch to Chinese");
  languageSwitch.dataset.language = language;

  try {
    localStorage.setItem(languageStorageKey, language);
  } catch {
    // File previews can deny storage; the current page still switches language.
  }
}

applyLanguage(savedLanguage());

languageSwitch.addEventListener("click", () => {
  applyLanguage(languageSwitch.dataset.language === "zh" ? "en" : "zh");
});

wechatButton.addEventListener("click", () => {
  wechatDialog.showModal();
});

wechatDialogClose.addEventListener("click", () => {
  wechatDialog.close();
});

wechatDialog.addEventListener("cancel", (event) => {
  event.preventDefault();
  wechatDialog.close();
});

wechatDialog.addEventListener("click", (event) => {
  if (event.target === wechatDialog) {
    wechatDialog.close();
  }
});
