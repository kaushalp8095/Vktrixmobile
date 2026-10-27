// Test fixture: 96x96 JPEG (indigo "K" plate) — shop logo / thumbnail ke liye.
//
// Asli app har logo ko JPEG me convert karke bhejti hai, aur server usi se
// 96px thumbnail banata hai. Isliye test bhi JPEG use karte hain (PNG nahi):
// backend thumbnail sirf JPEG decode kar sakta hai.
const String kTestLogoJpegBase64 =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wCEAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQFxQYGBcUFhYaHSUfGhsjHBYWICwg'
    'IyYnKSopGR8tMC0oMCUoKSgBBwcHCggKEwoKEygaFhooKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgo'
    'KCgoKCgoKCgoKP/AABEIAGAAYAMBEQACEQEDEQH/xAGiAAABBQEBAQEBAQAAAAAAAAAAAQIDBAUGBwgJCgsQAAIBAwMCBAMF'
    'BQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElK'
    'U1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV'
    '1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+gEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoLEQACAQIEBAMEBwUEBAABAncA'
    'AQIDEQQFITEGEkFRB2FxEyIygQgUQpGhscEJIzNS8BVictEKFiQ04SXxFxgZGiYnKCkqNTY3ODk6Q0RFRkdISUpTVFVWV1hZ'
    'WmNkZWZnaGlqc3R1dnd4eXqCg4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2dri'
    '4+Tl5ufo6ery8/T19vf4+fr/2gAMAwEAAhEDEQA/AOh+LPxI1S61640rRri5020sJnid4ZCkk0ikqSWU8KDnAzz1PYL9Ll+X'
    '0401UqLmcvuS/r+u/HVqtuyPJ69gwCgAoAKACgAoAKACgAoAKAPWPhN8SNUtdet9K1m4udStL+ZIkeaQvJDIxCghmPKk4yM8'
    'dR3DePmGX05U3Uprlcfua/r+u29Kq07M8nr2DAKACgAoAKACgAoAKACgAoAKACgAoAKACgDqtE+H3ifXNMh1HS9M8+zm3bJP'
    'tES5wxU8MwPUHtXHVx9ClJwnKzXk/wDIuNKUldIyvEfh/U/Dd8lnrVt9muHjEqp5ivlSSAcqSOqn8q2o16dePNTd0TKLi7My'
    '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';

/// `data:image/jpeg;base64,...` — jaisa server `logo_data` me bhejta hai
/// (`logo_thumb` ab transparent PNG hota hai, niche wala fixture).
const String kTestLogoDataUrl = 'data:image/jpeg;base64,$kTestLogoJpegBase64';

// 16x16 transparent PNG (indigo block, kinare alpha 0) — server ka naya
// `logo_thumb` aisa hi hota hai. Isse pata chalta hai ki app white plate
// nahi lagati jab logo transparent ho.
const String kTestLogoPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAJ0lEQVR42mNgGAWM6AL2gVv/49NwcL03ih4mSl0wasBgMGAUMDAAANKxBBBhyZPeAAAAAElFTkSuQmCC';
const String kTestLogoPngDataUrl = 'data:image/png;base64,$kTestLogoPngBase64';
