{%- if page.comments and not is_home() -%}
  <div class="comments" id="comments">
    {%- if theme.disqus.shortname -%}
      <div id="disqus_thread">
        <noscript>
          Please enable JavaScript to view the
          <a href="//disqus.com/?ref_noscript">comments powered by Disqus.</a>
        </noscript>
      </div>
    {%- elif theme.livere_datauid -%}
      <div id="lv-container" data-id="city" data-uid="{{ theme.livere_datauid }}">
        <noscript>为正常使用来必力评论功能请激活JavaScript</noscript>
      </div>  
    {%- elif theme.gitalk.enable -%}
      <div id="gitalk-container"></div>
    {%- elif theme.utterances.enable -%}
      <div id="utterances-container"></div>
    {%- elif theme.cusdis.app_id -%}
      <div id="cusdis_thread"
        data-host="{{ theme.cusdis.host || 'https://cusdis.com' }}"
        data-app-id="{{ theme.cusdis.app_id }}"
        data-page-id="{{ page.path }}"
        data-page-url="{{ page.permalink }}"
        data-page-title="{{ page.title }}"
      ></div>
    {%- endif -%}
  </div>
{%- endif -%}
