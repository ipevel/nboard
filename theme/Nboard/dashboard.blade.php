<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta http-equiv="X-UA-Compatible" content="ie=edge" />
    <!-- 静态头不写死品牌：标题与图标由下方引导脚本按后台站点配置即时填充 -->
    <title></title>
    <script>
      /*
       * 首屏语言标记：应用语言包尚未加载时，先按存储的语言或浏览器语言写入 html lang，
       * 避免文档语言声明与实际界面语言短暂不一致。应用内 i18n 加载后会再校准一次。
       */
      (function () {
        try {
          var stored = localStorage.getItem('language');
          var lang =
            stored === 'zh-CN' || stored === 'en-US'
              ? stored
              : (navigator.language || '').toLowerCase().indexOf('zh') === 0
                ? 'zh-CN'
                : 'en-US';
          document.documentElement.setAttribute('lang', lang);
        } catch (e) {
          /* 存储不可用时保留静态声明 */
        }
      })();
    </script>
    
    <script>
      /*
       * 站点品牌引导：在应用包加载前先取一次后台站点配置，让标签标题与图标在首帧就跟着后台，
       * 避免出现构建期静态值（旧项目名与旧图标）再被 JavaScript 覆盖的闪烁。
       * 取回的 Promise 挂在 window 上，应用内的站点配置请求直接复用，不额外发请求。
       */
      (function () {
        var cfg = (window.EZ_CONFIG || {}).API_CONFIG || {};
        var base = '/api/v1';

        if (cfg.urlMode === 'static' && cfg.staticBaseUrl && cfg.staticBaseUrl[0]) {
          base = String(cfg.staticBaseUrl[0]).replace(/\/+$/, '');
        } else if (typeof window !== 'undefined') {
          base = window.location.origin + '/api/v1';
        }

        window.__EZ_SITE_CONFIG_PROMISE__ = fetch(base + '/guest/comm/config')
          .then(function (res) {
            return res.json();
          })
          .then(function (json) {
            var d = (json && json.data) || {};

            document.title = d.app_name || 'Nboard';

            // 后台未配置 logo 时回退到主题内置的品牌图标
            var iconHref = d.logo || '/theme/Nboard/assets/images/logo.png';

            (function () {
              var link = document.querySelector('link[rel~="icon"]');

              if (!link) {
                link = document.createElement('link');
                link.setAttribute('rel', 'icon');
                document.head.appendChild(link);
              }

              link.removeAttribute('type');
              link.setAttribute('href', iconHref);
            })();

            return json;
          })
          .catch(function () {
            return null;
          });
      })();
    </script>
    <style>@media (width>=769px){html,body,div,main,section,article,aside,nav{scrollbar-width:none!important;-ms-overflow-style:none!important}::-webkit-scrollbar{background:0 0!important;width:0!important;height:0!important;display:none!important}::-webkit-scrollbar-button{background:0 0!important;width:0!important;height:0!important;display:none!important}::-webkit-scrollbar-track{background:0 0!important;width:0!important;height:0!important;display:none!important}::-webkit-scrollbar-track-piece{background:0 0!important;width:0!important;height:0!important;display:none!important}::-webkit-scrollbar-thumb{background:0 0!important;width:0!important;height:0!important;display:none!important}::-webkit-scrollbar-corner{background:0 0!important;width:0!important;height:0!important;display:none!important}::-webkit-resizer{background:0 0!important;width:0!important;height:0!important;display:none!important}}html,body{width:100%;height:100%}@media (width>=769px){*{scrollbar-width:none!important;-ms-overflow-style:none!important}}html,body{width:100%;height:100%;margin:0;padding:0;overflow-x:hidden}#app{width:100%;height:100%}html.preloader-active,body.preloader-active{overflow:hidden!important}</style>
    <script type="module" crossorigin src="/theme/Nboard/assets/static-generated/index-BgkpRHdI.js"></script>
      <link rel="modulepreload" crossorigin href="/theme/Nboard/assets/static-generated/vue-CZVGrrJU.js" />
    <script>
        // 已登录时把面板主包与共享分块也加入预载，与入口包并行下载，省掉串行往返
        (function () {
          try {
            if (!localStorage.getItem('token')) return;
            var urls = ['/theme/Nboard/assets/static-generated/appInit-DKedKfuh.js', '/theme/Nboard/assets/static-generated/vendor-AOGVQNaS.js', '/theme/Nboard/assets/static-generated/icons-DSM2tnkg.js'];
            urls.forEach(function (href) {
              var link = document.createElement('link');
              link.rel = 'modulepreload';
              link.crossOrigin = 'anonymous';
              link.href = href;
              document.head.appendChild(link);
            });
          } catch (e) {
            // 预载失败不影响正常加载
          }
        })();
      </script>
      <link rel="icon" type="image/png" sizes="32x32" href="/images/favicon-32x32.png">
    <link rel="icon" type="image/png" sizes="16x16" href="/images/favicon-16x16.png">
    <link rel="apple-touch-icon" sizes="180x180" href="/images/apple-touch-icon.png">
</head>
  <body>
    <div id="app"></div>
  </body>
</html>
