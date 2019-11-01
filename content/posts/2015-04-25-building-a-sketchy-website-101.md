---
layout: post
title: "Building a Sketchy Website 101"
date: 2015-04-25 17:42:10 -0400
comments: true
tags: [hacking, web, sysadmin]
---

Back in April, I won a free ".club" domain through gandi.net's
[anniversary](https://15.gandi.net) prize giveaway. I really didn't need
a ".club" domain in particular, so I thought it would be pretty fun to
register a stereotypical "sketchy" domain and set it up as a drive-by
download site or something, because while I've *heard* of doing this kind of
thing, I've never actually done it before. Here's a blog post walking through
what I did. The usual disclaimer applies here: I did this purely for my
own education and learning experience and am not responsible for anything
you do with it.

### Step 1: Register your sketchy domain

I chose [http://freemoviedownload.club](http://freemoviedownload.club).

### Step 2: Set up drive-by downloads

This involves configuring your web server to automatically set the
`Content-Type` header of the resource you want to force download
to `application/octet-stream`. That should make most web browsers trigger
a download file prompt to actually download the file. Safari curiously
doesn't support prompts for downloaded file location like Chrome and Firefox,
so in that case, it will immediately download the file to `~/Downloads`.

I'm going to try to force a drive-by download of a jpg file, so I added
the below config to my `.htaccess` file in Apache's `DocumentRoot`.

```xml .htaccess
<Files *.jpg>
        ForceType application/octet-stream
</Files>
```

That will force browers to download the image, rather than rendering it
when a browser tries to access `http://freemoviedownload.club/image.jpg`, for
example.

At this point, we're technically done. We can send someone a link to a file
and, assuming they say yes to the prompt (or use Safari), download it to their
computer.  But for some extra polish, I want to have an actual website with
content and have the download come from *that* page.

### Step 3: Redirect

We can accomplish this with a trivial Javascript redirect that executes
after the page has loaded. We can even add a delay before the download happens
to give them time to read the website or whatever. The redirect will need
to be to the path configured in step 2, but this will give the illusion that
the download is coming from the `index.html` page.

```html index.html
you have arrived at the official free movie download club! enjoy your download
<script type="text/javascript" charset="utf-8">
    function f() { document.location = 'dickbutt.jpg' }
    setTimeout(f, 2000);
</script>
```

That's it! Anyone that browses to the website will automatically get a nice
"dickbutt.jpg" image downloaded to their machine. Again, particularly effective
against Safari and Chrome for Android, in my testing.

![](/img/sketchy.gif)
