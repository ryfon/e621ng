import Blacklist from './blacklists';

const Thumbnails = {};

Thumbnails.initialize = function () {
  const clearPlaceholder = function (post) {
    if (post.hasClass('thumb-placeholder-link')) {
      post.removeClass('thumb-placeholder-link');
    } else {
      post.empty();
    }
  };
  const postsData = window.___deferred_posts || {};
  const posts = $('.post-thumb.placeholder, .thumb-placeholder-link');
  $.each(posts, function (i, post) {
    const p = $(post);
    const postID = p.data('id');
    if (!postID) {
      clearPlaceholder(p);
      return;
    }
    const postData = postsData[postID];
    if (!postData) {
      clearPlaceholder(p);
      return;
    }
    let blacklist_hit_count = 0;
    $.each(Blacklist.entries, function (j, entry) {
      if (Blacklist.post_match_object(postData, entry)) {
        entry.hits += 1;
        blacklist_hit_count += 1;
      }
    });
    const newTag = $('<div>');
    const blacklisted = blacklist_hit_count > 0;
    for (const key in postData) {
      newTag.data(key.replace(/_/g, '-'), postData[key]);
    }
    newTag.attr('class', blacklisted ? "post-thumbnail blacklisted blacklisted-active" : "post-thumbnail");
    if (p.hasClass('thumb-placeholder-link'))
      newTag.addClass('dtext');
    const img = $('<img>');
    img.attr('src', postData.preview_url);
    img.attr({
      height: postData.preview_height,
      width: postData.preview_width,
      title: `Rating: ${postData.rating}\r\nID: ${postData.id}\r\nStatus: ${postData.status}\r\n\r\n${postData.tags}`,
      alt: postData.tags,
      class: 'post-thumbnail-img'
    });
    const link = $('<a>');
    link.attr('href', `/posts/${postData.id}`);
    link.append(img);
    newTag.append(link);
    p.replaceWith(newTag);
  });
};

$(document).ready(function () {
  Thumbnails.initialize();
  $(document).on('thumbnails:apply', Thumbnails.initialize);
});

export default Thumbnails;