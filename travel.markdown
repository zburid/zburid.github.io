---
layout: page
title: 🏝
permalink: /travel/
---

旅行足迹

{% for cat in site.categories %}
{% if cat[0]=="travel" %}
  <ul>
    {% for post in cat[1] %}
      {% if post.show %}
        <li><a href="{{ post.url }}">{{ post.title }}</a></li>
      {% endif %}
    {% endfor %}
  </ul>
{% endif %}
{% endfor %}
