{%- if theme.disqus.shortname -%}
<script src="https://cdn.jsdelivr.net/npm/disqusjs@1.3/dist/disqus.js"></script>
<script type="text/javascript">
  var dsqjs = new DisqusJS({
      shortname: '{{ theme.disqus.shortname}}',
      identifier: '{{ page.path }}',
      url: '{{ page.permalink }}',
      title: '{{ page.title }}',
      api: '{{ theme.disqus.api }}',
      apikey: '{{ theme.disqus.apikey }}',
      admin: '{{ theme.disqus.admin }}',
      adminLabel: '{{ theme.disqus.adminLable }}'
  });
</script>
{%- endif -%}
