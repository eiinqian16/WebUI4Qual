(function (global) {
    var SUPPORTED_LANGS = ['en', 'ms', 'zh'];
    var DEFAULT_LANG = 'en';
    var STORAGE_KEY = 'webui_lang';

    var currentLang = DEFAULT_LANG;
    var dict = {};
    var fallbackDict = {};
    var initPromise = null;
    var langCache = {};

    function fetchLangFile(lang) {
        if (langCache[lang]) {
            return Promise.resolve(langCache[lang]);
        }
        return fetch('lang/' + lang + '.json', { cache: 'no-store' })
            .then(function (res) {
                if (!res.ok) throw new Error('Failed to load lang/' + lang + '.json');
                return res.json();
            })
            .then(function (json) {
                langCache[lang] = json;
                return json;
            });
    }

    function t(key, vars) {
        var str = key;
        if (dict && Object.prototype.hasOwnProperty.call(dict, key)) {
            str = dict[key];
        } else if (fallbackDict && Object.prototype.hasOwnProperty.call(fallbackDict, key)) {
            str = fallbackDict[key];
        }
        if (vars) {
            Object.keys(vars).forEach(function (k) {
                str = str.replace(new RegExp('\\{' + k + '\\}', 'g'), vars[k]);
            });
        }
        return str;
    }

    function applyTranslations(root) {
        root = root || document;
        if (!root.querySelectorAll) return;

        root.querySelectorAll('[data-i18n]').forEach(function (el) {
            el.textContent = t(el.getAttribute('data-i18n'));
        });
        root.querySelectorAll('[data-i18n-placeholder]').forEach(function (el) {
            el.setAttribute('placeholder', t(el.getAttribute('data-i18n-placeholder')));
        });
        root.querySelectorAll('[data-i18n-title]').forEach(function (el) {
            el.setAttribute('title', t(el.getAttribute('data-i18n-title')));
        });
        root.querySelectorAll('[data-i18n-value]').forEach(function (el) {
            el.setAttribute('value', t(el.getAttribute('data-i18n-value')));
        });
        root.querySelectorAll('[data-i18n-aria-label]').forEach(function (el) {
            el.setAttribute('aria-label', t(el.getAttribute('data-i18n-aria-label')));
        });
        root.querySelectorAll('[data-i18n-html]').forEach(function (el) {
            el.innerHTML = t(el.getAttribute('data-i18n-html'));
        });

        document.dispatchEvent(new CustomEvent('i18n:applied', { detail: { lang: currentLang } }));
    }

    function persistLangToRouter(lang) {
        return fetch('/cgi-bin/save_lang.sh', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: 'lang=' + encodeURIComponent(lang)
        }).catch(function (err) {
            console.warn('Could not persist language to router:', err);
        });
    }

    function setLanguage(lang, opts) {
        opts = opts || {};
        if (SUPPORTED_LANGS.indexOf(lang) === -1) lang = DEFAULT_LANG;

        return fetchLangFile(lang).then(function (json) {
            dict = json;
            currentLang = lang;
            document.documentElement.lang = lang;
            try { localStorage.setItem(STORAGE_KEY, lang); } catch (e) { /* storage unavailable */ }

            applyTranslations(document);

            if (opts.persist === false) {
                return lang;
            }
            return persistLangToRouter(lang).then(function () { return lang; });
        });
    }

    function detectInitialLang() {
        return fetch('/cgi-bin/get_lang.sh', { cache: 'no-store' })
            .then(function (res) { return res.ok ? res.json() : Promise.reject(new Error('get_lang.sh failed')); })
            .then(function (data) { return data && data.lang; })
            .catch(function () {
                try { return localStorage.getItem(STORAGE_KEY); } catch (e) { return null; }
            });
    }

    function init() {
        if (initPromise) return initPromise;

        initPromise = fetchLangFile(DEFAULT_LANG)
            .then(function (json) { fallbackDict = json; })
            .catch(function () { fallbackDict = {}; })
            .then(function () { return detectInitialLang(); })
            .then(function (lang) { return setLanguage(lang || DEFAULT_LANG, { persist: false }); });

        return initPromise;
    }

    global.i18n = {
        init: init,
        t: t,
        applyTranslations: applyTranslations,
        setLanguage: setLanguage,
        SUPPORTED_LANGS: SUPPORTED_LANGS,
        get currentLang() { return currentLang; }
    };

    global.t = t;
})(window);
