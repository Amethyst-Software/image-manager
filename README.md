# Media Manager
This script allows you to search a directory for images and movie files by certain criteria, then perform various operations on them. You can replace the original media with your changed versions, save the altered versions beside the originals or place them in a mirrored directory. This script requires ImageMagick to operate on images and FFmpeg to operate on videos.

The full documentation for the script, including additional nuances of the options below, can be seen by running Media Manager without any arguments. Here are the criteria by which you can filter media:
- File name or suffix.
- Type (image or movie).
- Width/height (less than, equal to or greater than).
- Aspect ratio (landscape, portrait, square or a precise ratio like 16:9).

Here are the operations you can currently perform on the media which meet your criteria:
- Append the dimensions of the media to its file name.
- Crop the media to a certain width and/or height.
- Resize the media to a relative percentage or an absolute width/height.
- Flip the media horizontally and/or vertically.
- Rotate the media any number of degrees.
- Trim movies between start and end times.
- Speed up/slow down movies.
- Convert the media to another format.

![Preview](https://github.com/Amethyst-Software/media-manager/blob/main/preview.png)