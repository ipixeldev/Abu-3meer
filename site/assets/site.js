(() => {
  const root = document.documentElement;
  const stored = localStorage.getItem('abu3meer-language');
  const initial = stored || (navigator.language.startsWith('ar') ? 'ar' : 'en');

  function setLanguage(value) {
    const language = value === 'ar' ? 'ar' : 'en';
    root.lang = language;
    root.dir = language === 'ar' ? 'rtl' : 'ltr';
    localStorage.setItem('abu3meer-language', language);
    document.querySelectorAll('[data-language]').forEach((button) => {
      button.setAttribute(
        'aria-pressed',
        String(button.dataset.language === language),
      );
    });
  }

  document.querySelectorAll('[data-language]').forEach((button) => {
    button.addEventListener('click', () => setLanguage(button.dataset.language));
  });

  setLanguage(initial);
})();
