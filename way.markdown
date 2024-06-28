---
layout: page
title: ☯️
permalink: /way/
---

数据分析

{% for cat in site.categories %}
{% if cat[0]=="way" %}
  <ul>
    {% for post in cat[1] %}
      {% if post.show %}
        <li><a href="{{ post.url }}">{{ post.title }}</a></li>
      {% endif %}
    {% endfor %}
  </ul>
{% endif %}
{% endfor %}
