# Image Manager
This script allows you to search a directory for images by certain criteria, then perform various operations on them. You can replace the original images with your changed versions, save the altered versions beside the originals or place them in a mirrored directory. This script requires ImageMagick to run.

The full documentation for the script, including additional nuances of the options below, can be seen by running Image Manager without any arguments. Here are the criteria by which you can filter images:
- Width/height (less than, equal to or greater than).
- File suffix.
- Aspect ratio (landscape, portrait, square or a precise ratio like 16:9).

Here are the operations you can currently perform on the images which meet your criteria:
- Append the dimensions of the image to its file name.
- Crop the image to a certain width and/or height.
- Resize the image to a certain percentage, width and/or height.
- Flip the image horizontally and/or vertically.
- Rotate the image any number of degrees.
- Convert the image to another format.

![Preview](https://github.com/Amethyst-Software/image-manager/blob/main/preview.png)