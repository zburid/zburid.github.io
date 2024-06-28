---
layout: page
title: 📕
permalink: /books/
---

读书列表

{% for cat in site.categories %}
{% if cat[0]=="books" %}
  <ul>
    {% for post in cat[1] %}
      <li><a href="{{ post.url }}">{{ post.title }}</a></li>
    {% endfor %}
  </ul>
{% endif %}
{% endfor %}
