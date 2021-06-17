---
layout: page
title: 🐳
permalink: /fishes/
---

摸鱼列表

{% for cat in site.categories %}
{% if cat[0]=="fishes" %}
  <ul>
    {% for post in cat[1] %}
      {% if post.show %}
        <li><a href="{{ post.url }}">{{ post.title }}</a></li>
      {% endif %}
    {% endfor %}
  </ul>
{% endif %}
{% endfor %}
