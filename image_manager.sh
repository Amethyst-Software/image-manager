#!/bin/bash

# Image Manager
# Recursively searching a directory for images, you can filter for only images of
# certain dimensions, a certain format, and a certain aspect ratio. You can print
# the resulting file names to screen, label files with their dimensions, convert
# the files to a new format, crop them and scale them. You can replace the original
# images with your changed versions, save the altered versions beside the
# originals, or save them in a mirrored directory. Call script without arguments
# for usage details.
# Requires ImageMagick to be installed.
# Recommended width:
# |---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ----|

IFS="
"

## CONSTANTS ##
declare -a IMG_SUFF=(bmp dds gif jpeg jpg png tga tif tiff)
COLS=$(tput cols)
BOLD=$(tput bold)
UNDR=$(tput smul)
NORM=$(tput sgr0)
FILE_OVERWRITE=1
FILE_BESIDE=2
FILE_MIRROR=3
CROP_WIDTH_ONLY=1
CROP_HEIGHT_ONLY=2
CROP_WIDTH_HEIGHT=3
CROP_ALIGN_H_LEFT=1
CROP_ALIGN_H_CENTER=2
CROP_ALIGN_H_RIGHT=3
CROP_ALIGN_V_TOP=1
CROP_ALIGN_V_CENTER=2
CROP_ALIGN_V_BOTTOM=3
SCALE_WIDTH_ONLY=1
SCALE_HEIGHT_ONLY=2
SCALE_WIDTH_HEIGHT=3
SCALE_PERCENT=4

## SETTINGS VARIABLES ##
FILE_MODE=0 # can be set to one of the FILE_* constants above
SOURCE_DIR=""
SHOW_SKIPS=0 # boolean
COPY_SKIPS=0 # boolean
SOURCE_FORMAT=""
SOURCE_WIDTH_FILTER=0 # boolean
SOURCE_WIDTH_PX=0
SOURCE_WIDTH_OP=""
SOURCE_WIDTH_OP_NAME=""
SOURCE_HEIGHT_FILTER=0 # boolean
SOURCE_HEIGHT_PX=0
SOURCE_HEIGHT_OP=""
SOURCE_HEIGHT_OP_NAME=""
SOURCE_ORIENT_FILTER=0 # boolean
SOURCE_ORIENT=""
SOURCE_RATIO_FILTER=0 # boolean
SOURCE_RATIO_W=0 # integer
SOURCE_RATIO_H=0 # integer
SOURCE_RATIO=0 # floating-point number
SOURCE_RATIO_FUZZ_PERC=1 # percent as a floating-point number from 0-100
SOURCE_RATIO_FUZZ=0 # floating-point number
CROP_WIDTH=0
CROP_HEIGHT=0
CROP_OFFSET_X=0
CROP_OFFSET_Y=0
CROP_ALIGN_H=$CROP_ALIGN_H_LEFT # set to one of the CROP_ALIGN_H_* constants above
CROP_ALIGN_V=$CROP_ALIGN_V_TOP # set to one of the CROP_ALIGN_V_* constants above
CROP_TYPE=0 # can be set to one of the CROP_* constants above
SCALE_WIDTH=0
SCALE_HEIGHT=0
SCALE_PERC=0
DEST_DIR=""
OPER_PRINT=0 # boolean
OPER_LABEL=0 # boolean
OPER_CONVERT=0 # boolean
OPER_CROP=0 # boolean
OPER_SCALE=0 # boolean
SCALE_TYPE=0 # can be set to one of the SCALE_* constants above
NEW_TYPE=""
DRY_RUN=0 # boolean

## SUPPORTING FUNCTIONS ##
# Trim a string before or after a separator, returning the remainder. Syntax is
# "trim string [before/after] [first/last] separator", where separator can be a
# single character or a string. If the user does something wrong, which includes
# supplying a separator that doesn't exist in the string, an empty string will be
# returned along with an error code.
function trim()
{
   if [ "$#" -lt 4 ]; then
      echo ""
      echo "trim(): Not enough arguments!" > /dev/stderr
      return 1
   fi

   # If the separator doesn't exist in the string, return nothing
   WITH=$(echo $1 | wc -c)
   WITHOUT=$(echo ${1%%$4*} | wc -c)
   if [ $WITH -eq $WITHOUT ]; then
      echo ""
      echo "trim(): Separator '$4' not found in '$1'!" > /dev/stderr
      return 2
   fi

   if [ $2 == "before" ]; then
      if [ $3 == "first" ]; then
         echo ${1%%$4*}
      elif [ $3 == "last" ]; then
         echo ${1%$4*}
      else
         echo ""
         echo "trim(): Expected 'first' or 'last' after 'before'!" > /dev/stderr
         return 3
      fi
   elif [ $2 == "after" ]; then
      if [ $3 == "first" ]; then
         echo ${1#*$4}
      elif [ $3 == "last" ]; then
         echo ${1##*$4}
      else
         echo ""
         echo "trim(): Expected 'first' or 'last' after 'after'!" > /dev/stderr
         return 4
      fi
   else
      echo ""
      echo "trim(): Expected 'before' or 'after', got '$2'!" > /dev/stderr
      return 5
   fi
}

# Round a floating point number to an integer. If the argument passed in is not a
# number, zero is returned.
function round()
{
   if [[ ! "$1" =~ ^-{0,1}[0-9]+\.{0,1}[0-9]*$ ]]; then
      printf "0"
      return
   fi

   if [[ "$1" =~ ^-.*$ ]]; then
      echo $1 | awk '{printf "%d",int($1 - 0.5)}'
   else # positive number
      echo $1 | awk '{printf "%d",int($1 + 0.5)}'
   fi
}

# For word-wrapped output
function mypr()
{
   echo $1 | fmt -w $COLS
}

# For bold word-wrapped output
function myprb()
{
   echo -e "${BOLD}$1${NORM}" | fold -s -w $COLS
}

# For centered output
function myprc()
{
   echo $1 | fmt -w $COLS -c
}

# For debug output, toggled on and off by --show-skips
function myprd()
{
   if [ $SHOW_SKIPS -eq 1 ]; then
      echo $1 | fmt -w $COLS
   fi
}

# For formatted output; each line of input has underscores converted to underline
# markup and pipes converted to bold markup. For simplicity's sake, there are two
# assumptions: that bold and underline are only used twice per line, and that each
# format tag is opened and closed on the same line.
function myprf()
{
   while (( "$#" )); do
      TEXT=$(echo "$1" | sed "s/_/${UNDR}/1" | sed "s/_/${NORM}/1")
      TEXT=$(echo "$TEXT" | sed "s/_/${UNDR}/1" | sed "s/_/${NORM}/1")
      TEXT=$(echo "$TEXT" | sed "s/|/${BOLD}/1" | sed "s/|/${NORM}/1")
      TEXT=$(echo "$TEXT" | sed "s/|/${BOLD}/1" | sed "s/|/${NORM}/1")
      echo "$TEXT"
      shift
   done
}

# Print help page for script
# 80-column margin for help text:
# |----------------------------------------------------------------------------|
function printHelp()
{
   echo -n ${BOLD}
   myprc "--Image Manager Help--"
   echo -n ${NORM}
   MAN_TEXT="|You must supply the following argument:|
   _--in-dir PATH_: The directory to look in recursively for image files.

|You must choose one of the following file modes if you are performing an opera-|
|tion on the images and not just searching for them:|
   _--overwrite_ will replace each original image with the changed version.
   _--beside_ will rename the original image to '[original name]-old' and place
      the new image at the original image's location, unless you have supplied
      the argument _--label_, in which case the original image's name will remain
      unchanged.
   _--dest PATH_ will place new images in the directory _PATH_, which must already
      exist. The hierarchy of the original directory will be duplicated.
      _--copy-skips_ is a sub-option of _--dest PATH_ which tells the script to
         also copy images that were not altered. You will be able to differen-
         tiate these from the altered images because they will retain their
         original timestamps. If you have specified a format filter with the
         _--only-format:SUF_ argument, files that don't match the desired format
         will not be copied, but files that fail any other filter will be copied
         to the destination directory.

|You may utilize any or all of the following operations, or specify no operation|
|to simply print the names of all files matching your filters (if both a crop and|
|scale operation are requested, the crop will be performed first):|
   _--label_ will add the size of each image to its name. If you ask for a label
      in addition to specifying some operation(s) to be performed on the images,
      the label will be applied to the new image.
   _--convert-to:SUF_ with the suffix of the file type you want, e.g.
      _--convert-to:jpg_.
   _--crop-width:NUM_ and/or _--crop-height:NUM_ will trim the image to the desired
      width and/or height.
   _--crop-offset-x:NUM_ will offset the crop from the left side of the image by
      the specified number of pixels.
   Add the _--crop-align-right_ argument to make the _--crop-width:NUM_ and
      _--crop-offset-x:NUM_ arguments start from the right of the image instead
      of the left.
   Alternately, use _--crop-center-h_ to crop from the horizontal center. For
      example, _--crop-center-h --crop-width:101_ will crop the image down to a
      101px-wide section from its center (to be exact, 50px to the left and 51px
      to the right). In this case the _--crop-offset-x:NUM_ argument can use a
      positive or negative number to shift the crop area to the left and right
      of center.
   _--crop-offset-y:NUM_ will offset the crop from the top of the image by the
      specified number of pixels.
   Add the _--crop-align-bottom_ argument to make the _--crop-height:NUM_ and
      _--crop-offset-y:NUM_ arguments start from the bottom of the image instead
      of the top.
   Alternately, use _--crop-center-v_ to crop from the vertical center. The ex-
      planation of _--crop-center-h_ above applies here as well.
   _--scale-percent:NUM_ will scale each image by this percentage of its size,
      e.g. _--scale-percent:50_ will reduce an image to 50% of its current size.
   _--scale-width:NUM_ and/or _--scale-height:NUM_ give the width and/or height to
      which the image should be resized. If you specify both a new width and
      height, the image will be squashed or stretched if the new proportions are
      not equal to the original proportions. If you only specify a new width or
      a new height, the scaling will take place proportionally.

|You may use these arguments to limit which images will be operated upon:|
   _--only-format:SUF_: Only select images with the suffix _SUF_.
   Choose one of the following width arguments:
   _--only-width-eq:NUM_: Only choose images that have width _NUM_ in pixels.
   _--only-width-lt:NUM_: Only select images that have width < _NUM_ pixels.
   _--only-width-le:NUM_: Only select images that have width ≤ _NUM_ pixels.
   _--only-width-gt:NUM_: Only select images that have width > _NUM_ pixels.
   _--only-width-ge:NUM_: Only select images that have width ≥ _NUM_ pixels.
   Choose one of the following height arguments:
   _--only-height-eq:NUM_: Only select images that have height _NUM_ in pixels.
   _--only-height-lt:NUM_: Only select images that have height < _NUM_ pixels.
   _--only-height-le:NUM_: Only select images that have height ≤ _NUM_ pixels.
   _--only-height-gt:NUM_: Only select images that have height > _NUM_ pixels.
   _--only-height-ge:NUM_: Only select images that have height ≥ _NUM_ pixels.
   _--only-orient:STR_: Select images which have a certain orientation. _STR_
      should be 'port' for portrait, 'land' for landscape, and 'square' for
      images of exactly the same height and width.
   _--only-ratio:NUM:NUM_: Select images which have a certain aspect ratio, e.g.
      _--only-ratio:16:9_.
   _--only-ratio-fuzz:NUM_: Because of slight decimal differences, some images
      may not precisely match your _--only-ratio_ argument. For instance, a
      1366x768 image is considered 16:9, but it's actually a ratio of 1.77865…
      whereas 16:9 is 1.77777…, a deviation of about 0.05%. The fuzziness is
      already set to a default of 1.0%, but you can set it higher or lower with
      this argument.
|You also have the following arguments available for troubleshooting purposes:|
   _--dry-run_: Print out the command which would be run on each file instead of
      performing the command.
   _--show-skips_: Print name of each file that was excluded by the chosen
      filters and the reason why it was excluded."
   myprf "$MAN_TEXT"
}

# Take apart an argument starting with "--only" and save as filter
function processOnlyArg()
{
   if [[ $1 == *format* ]]; then
      SOURCE_FORMAT=$(trim "$1" after first :)
      if [ -z $SOURCE_FORMAT ]; then
         mypr "Error 1: Failed to find suffix at end of '--only-format:' argument."
         exit 1
      fi
   elif [[ $1 == *width* ]]; then
      SOURCE_WIDTH_FILTER=1
      SOURCE_WIDTH_PX=$(trim "$1" after first :)
      SOURCE_WIDTH_PX=$(round $SOURCE_WIDTH_PX)
      if [ -z $SOURCE_WIDTH_PX ] || [ $SOURCE_WIDTH_PX -lt 1 ]; then
         mypr "Error 2: Failed to parse number in '--only-width-*:NUM' argument or NUM was less than 1."
         exit 2
      fi

      SOURCE_WIDTH_OP=$(trim "$1" after first "--only-width")
      SOURCE_WIDTH_OP=$(trim "$SOURCE_WIDTH_OP" before first :)
      if [ "$SOURCE_WIDTH_OP" == "-eq" ]; then
         SOURCE_WIDTH_OP_NAME=""
      elif [ "$SOURCE_WIDTH_OP" == "-lt" ]; then
         SOURCE_WIDTH_OP_NAME="less than "
      elif [ "$SOURCE_WIDTH_OP" == "-le" ]; then
         SOURCE_WIDTH_OP_NAME="less than or equal to "
      elif [ "$SOURCE_WIDTH_OP" == "-gt" ]; then
         SOURCE_WIDTH_OP_NAME="greater than "
      elif [ "$SOURCE_WIDTH_OP" == "-ge" ]; then
         SOURCE_WIDTH_OP_NAME="greater than or equal to "
      else
         mypr "Error 3: Failed to find operation 'eq', 'lt', 'le', 'gt', or 'ge' in '--only-width-*:NUM' argument."
         exit 3
      fi
   elif [[ $1 == *height* ]]; then
      SOURCE_HEIGHT_FILTER=1
      SOURCE_HEIGHT_PX=$(trim "$1" after first :)
      SOURCE_HEIGHT_PX=$(round $SOURCE_HEIGHT_PX)
      if [ -z $SOURCE_HEIGHT_PX ] || [ $SOURCE_HEIGHT_PX -lt 1 ]; then
         mypr "Error 4: Failed to parse number in '--only-height-*:NUM' argument or NUM was less than 1."
         exit 4
      fi

      SOURCE_HEIGHT_OP=$(trim "$1" after first "--only-height")
      SOURCE_HEIGHT_OP=$(trim "$SOURCE_HEIGHT_OP" before first :)
      if [ "$SOURCE_HEIGHT_OP" == "-eq" ]; then
         SOURCE_HEIGHT_OP_NAME=""
      elif [ "$SOURCE_HEIGHT_OP" == "-lt" ]; then
         SOURCE_HEIGHT_OP_NAME="less than "
      elif [ "$SOURCE_HEIGHT_OP" == "-le" ]; then
         SOURCE_HEIGHT_OP_NAME="less than or equal to "
      elif [ "$SOURCE_HEIGHT_OP" == "-gt" ]; then
         SOURCE_HEIGHT_OP_NAME="greater than "
      elif [ "$SOURCE_HEIGHT_OP" == "-ge" ]; then
         SOURCE_HEIGHT_OP_NAME="greater than or equal to "
      else
         mypr "Error 5: Failed to find operation 'eq', 'lt', 'le', 'gt', or 'ge' in '--only-height-*:NUM' argument."
         exit 5
      fi
   elif [[ $1 == *orient* ]]; then
      SOURCE_ORIENT_FILTER=1
      SOURCE_ORIENT=$(trim "$1" after first :)
      if [ $SOURCE_ORIENT != "port" ] && [ $SOURCE_ORIENT != "land" ] && [ $SOURCE_ORIENT != "square" ]; then
         mypr "Error 6: Failed to find orientation 'port', 'land' or 'square' in '--only-orient:STR' argument."
         exit 6
      fi
	elif [[ $1 == *fuzz* ]]; then
      SOURCE_RATIO_FUZZ_PERC=$(trim "$1" after first :)
      SOURCE_RATIO_FUZZ_PERC=$(round $SOURCE_RATIO_FUZZ_PERC)
      if [ -z $SOURCE_RATIO_FUZZ_PERC ] || [ $SOURCE_RATIO_FUZZ_PERC -lt 0 ] || [ $SOURCE_RATIO_FUZZ_PERC -gt 99 ]; then
         mypr "Error 7: Failed to parse number in '--only-ratio-fuzz:NUM' argument or NUM was less than 0 or more than 99."
         exit 7
      fi

		# If we have already received the --only-ratio argument, compute final fuzz;
      # also calculated below under the "elif [[ $1 == *ratio* ]]" block in case
      # ratio is passed in after fuzz
		if [ ! -z $SOURCE_RATIO_W ]; then
			SOURCE_RATIO_FUZZ=$(echo | awk -v r=$SOURCE_RATIO -v f=$SOURCE_RATIO_FUZZ_PERC '{printf "%f",r*(f/100)}')
		fi
   elif [[ $1 == *ratio* ]]; then
      SOURCE_RATIO_FILTER=1
      RATIO_FULL=$(trim "$1" after first :)
      SOURCE_RATIO_W=$(trim "$RATIO_FULL" before first :)
      SOURCE_RATIO_W=$(round $SOURCE_RATIO_W)
      if [ -z $SOURCE_RATIO_W ] || [ "$SOURCE_RATIO_W" -lt 1 ]; then
         mypr "Error 8: Could not extract width component of aspect ratio from '--only-ratio:NUM:NUM' argument or width was less than 1."
         exit 8
      fi

      SOURCE_RATIO_H=$(trim "$RATIO_FULL" after first :)
      SOURCE_RATIO_H=$(round $SOURCE_RATIO_H)
      if [ -z $SOURCE_RATIO_H ] || [ "$SOURCE_RATIO_H" -lt 1 ]; then
         mypr "Error 9: Could not extract height component of aspect ratio from '--only-ratio:NUM:NUM' argument or height was less than 1."
         exit 9
      fi
      SOURCE_RATIO=$(echo | awk -v w=$SOURCE_RATIO_W -v h=$SOURCE_RATIO_H '{printf "%f",w/h}')
      # Compute how much of a margin we have; gets re-calculated above under the
      # "elif [[ $1 == *fuzz* ]]" block in case the user passes in a custom fuzz
      # argument after the ratio
		SOURCE_RATIO_FUZZ=$(echo | awk -v r=$SOURCE_RATIO -v f=$SOURCE_RATIO_FUZZ_PERC '{printf "%f",r*(f/100)}')
   else
      mypr "Error 10: Argument '$1' began with '--only' but wasn't followed by '-format', '-width', '-height', '-orient', '-fuzz' or '-ratio'. Run this script without arguments for help."
      exit 10
   fi
}

# Take apart an argument starting with "--crop" and save as operation
function processCropArg()
{
   if [[ $1 == *width* ]]; then
      CROP_WIDTH=$(trim "$1" after first :)
      CROP_WIDTH=$(round $CROP_WIDTH)
      if [ -z $CROP_WIDTH ] || [ $CROP_WIDTH -lt 1 ]; then
         mypr "Error 11: Failed to parse number in '--crop-width:NUM' argument or NUM was less than 1."
         exit 11
      fi

      if [ $CROP_TYPE -eq $CROP_HEIGHT_ONLY ]; then
         CROP_TYPE=$CROP_WIDTH_HEIGHT
      else # user did not give a height for cropping
         CROP_TYPE=$CROP_WIDTH_ONLY
      fi
   elif [[ $1 == *height* ]]; then
      CROP_HEIGHT=$(trim "$1" after first :)
      CROP_HEIGHT=$(round $CROP_HEIGHT)
      if [ -z $CROP_HEIGHT ] || [ $CROP_HEIGHT -lt 1 ]; then
         mypr "Error 12: Failed to parse number in '--crop-height:NUM' argument or NUM was less than 1."
         exit 12
      fi

      if [ $CROP_TYPE -eq $CROP_WIDTH_ONLY ]; then
         CROP_TYPE=$CROP_WIDTH_HEIGHT
      else # user did not give a width for cropping
         CROP_TYPE=$CROP_HEIGHT_ONLY
      fi
   elif [[ $1 == *offset-x* ]]; then
      CROP_OFFSET_X=$(trim "$1" after first :)
      CROP_OFFSET_X=$(round $CROP_OFFSET_X)
      if [ -z $CROP_OFFSET_X ]; then
         mypr "Error 13: Failed to parse number in '--crop-offset-x:NUM' argument."
         exit 13
      fi
   elif [[ $1 == *offset-y* ]]; then
      CROP_OFFSET_Y=$(trim "$1" after first :)
      CROP_OFFSET_Y=$(round $CROP_OFFSET_Y)
      if [ -z $CROP_OFFSET_Y ]; then
         mypr "Error 14: Failed to parse number in '--crop-offset-y:NUM' argument."
         exit 14
      fi
   elif [[ $1 == *align-right* ]]; then
      CROP_ALIGN_H=$CROP_ALIGN_H_RIGHT
   elif [[ $1 == *align-bottom* ]]; then
      CROP_ALIGN_V=$CROP_ALIGN_V_BOTTOM
   elif [[ $1 == *center-h* ]]; then
      CROP_ALIGN_H=$CROP_ALIGN_H_CENTER
   elif [[ $1 == *center-v* ]]; then
      CROP_ALIGN_V=$CROP_ALIGN_V_CENTER
   else
      mypr "Error 15: Argument '$1' began with '--crop' but wasn't followed by '-width', '-height' or a valid '-offset-', '-align-' or '-center' term. Run this script without arguments for help."
      exit 15
   fi
}

# Take apart an argument starting with "--scale" and save as operation
function processScaleArg()
{
   if [[ $1 == *width* ]]; then
      SCALE_WIDTH=$(trim "$1" after first :)
      SCALE_WIDTH=$(round $SCALE_WIDTH)
      if [ -z $SCALE_WIDTH ] || [ $SCALE_WIDTH -lt 1 ]; then
         mypr "Error 16: Failed to parse number in '--scale-width:NUM' argument or NUM was less than 1."
         exit 16
      fi

      if [ $SCALE_TYPE -eq $SCALE_HEIGHT_ONLY ]; then
         SCALE_TYPE=$SCALE_WIDTH_HEIGHT
      else # user did not give a height for scaling
         SCALE_TYPE=$SCALE_WIDTH_ONLY
      fi
   elif [[ $1 == *height* ]]; then
      SCALE_HEIGHT=$(trim "$1" after first :)
      SCALE_HEIGHT=$(round $SCALE_HEIGHT)
      if [ -z $SCALE_HEIGHT ] || [ $SCALE_HEIGHT -lt 1 ]; then
         mypr "Error 17: Failed to parse number in '--scale-height:NUM' argument or NUM was less than 1."
         exit 17
      fi

      if [ $SCALE_TYPE -eq $SCALE_WIDTH_ONLY ]; then
         SCALE_TYPE=$SCALE_WIDTH_HEIGHT
      else # user did not give a width for scaling
         SCALE_TYPE=$SCALE_HEIGHT_ONLY
      fi
   elif [[ $1 == *percent* ]]; then
      SCALE_PERC=$(trim "$1" after first :)
      SCALE_PERC=$(round $SCALE_PERC)
      if [ -z $SCALE_PERC ] || [ $SCALE_PERC -lt 1 ]; then
         mypr "Error 18: Failed to parse number in '--scale-percent:NUM' argument or NUM was less than 1."
         exit 18
      fi

      SCALE_TYPE=$SCALE_PERCENT
   else
      mypr "Error 19: Argument '$1' began with '--scale' but wasn't followed by '-width', '-height' or '-percent'. Run this script without arguments for help."
      exit 19
   fi
}

# If user has supplied the --copy-skips argument, copy the file passed in even
# though it was not modified
function considerCopy()
{
   if [ $FILE_MODE -eq $FILE_MIRROR ] && [ $COPY_SKIPS -eq 1 ]; then
      # Create path in new dir. equivalent to path in orig. dir.
      MIRR_PATH=$(trim "$1" after first "$SOURCE_DIR/")
      MIRR_PATH=$(dirname "$MIRR_PATH")
      BASE_FILE_NAME=$(basename "$1")

      if [ "$MIRR_PATH" == "." ]; then
         MIRR_PATH=""
      else
         MIRR_PATH+="/"
      fi

      if [ $DRY_RUN -eq 0 ]; then
         if [ ! -d "$DEST_DIR/$MIRR_PATH" ]; then
            mkdir -p "$DEST_DIR/$MIRR_PATH"
         fi

         mypr "Copying unaltered file $BASE_FILE_NAME..."
         cp "$1" "$DEST_DIR/${MIRR_PATH}$BASE_FILE_NAME"
      else
         echo mkdir -p "$DEST_DIR/$MIRR_PATH"

         echo cp "$1" "$DEST_DIR/${MIRR_PATH}$BASE_FILE_NAME"
      fi
   fi
}

## CODE START ##
# Check for ImageMagick; specifically we need 'identify' and 'convert'
which identify > /dev/null
if [ "$?" -ne 0 ]; then
   mypr "Error 20: ImageMagick does not appear to be installed."
   exit 20
fi

# The script cannot perform any action with less than three arguments, so print
# the documentation (this also covers the case where the user guesses at an
# argument like "--help")
if [ "$#" -lt 3 ]; then
   printHelp
   exit
fi

# Process all arguments
while (( "$#" )); do
   # Shift 2 spaces unless that takes us past the end of the argument array, which
   # seems to hang the shell
   SAFE_2=2
   if [ "$#" -eq 1 ]; then
      SAFE_2=1
   fi

   case "$1" in
      --in-dir )      SOURCE_DIR="$2"; shift $SAFE_2;;
      --overwrite )   FILE_MODE=$FILE_OVERWRITE; shift;;
      --beside )      FILE_MODE=$FILE_BESIDE; shift;;
      --dest )        FILE_MODE=$FILE_MIRROR; DEST_DIR="$2"; shift $SAFE_2;;
      --copy-skips )  COPY_SKIPS=1; shift;;
      --label )       OPER_LABEL=1; shift;;
      --convert-to* ) NEW_TYPE=$(trim "$1" after first :); OPER_CONVERT=1; shift;;
      --crop* )       processCropArg $1; OPER_CROP=1; shift;;
      --scale* )      processScaleArg $1; OPER_SCALE=1; shift;;
      --only* )       processOnlyArg $1; shift;;
      --dry-run )     DRY_RUN=1; shift;;
      --show-skips )  SHOW_SKIPS=1; shift;;
      * )             mypr "Error 21: Unrecognized argument '$1'."; exit 21;;
   esac
done

# If no specific operation was requested, we'll just print the names to screen
if [ $OPER_LABEL -eq 0 ] && [ $OPER_CONVERT -eq 0 ] && [ $OPER_CROP -eq 0 ] && [ $OPER_SCALE -eq 0 ]; then
   OPER_PRINT=1
fi

## SAFETY CHECKS ##
if [ -z $SOURCE_DIR ]; then
   mypr "Error 22: You need to specify a directory to search using '--in-dir PATH'."
   exit 22
fi

if [ ! -d "$SOURCE_DIR" ]; then
   mypr "Error 23: The directory '$SOURCE_DIR' specified with '--in-dir' does not exist."
   exit 23
fi

if [ $FILE_MODE -eq 0 ]; then
   if [ $OPER_LABEL -eq 1 ] || [ $OPER_CONVERT -eq 1 ] || [ $OPER_CROP -eq 1 ] || [ $OPER_SCALE -eq 1 ]; then
      mypr "Error 24: Because you asked for a file operation to be performed, you need to specify the file mode with '--overwrite', '--beside', or '--dest PATH'. Run this script without arguments for help."
      exit 24
   fi
fi

if [ $FILE_MODE -eq $FILE_MIRROR ]; then
   if [ -z $DEST_DIR ]; then
      mypr "Error 25: You need to specify a destination path after the '--dest' argument."
      exit 25
   fi

   if [ ! -d "$DEST_DIR" ]; then
      mypr "Error 26: The directory '$DEST_DIR' specified with '--dest' does not exist."
      exit 26
   fi
fi

if [[ $OPER_PRINT -eq 1 && ( $FILE_MODE -ne 0 || $COPY_SKIPS -ne 0 ) ]]; then
   mypr "Error 27: Since you only opted to print file results rather than alter any files, you should not have specified a file operation mode."
   exit 27
fi

if [ $OPER_CROP -eq 1 ] && [ $CROP_WIDTH -eq 0 ] && [ $CROP_HEIGHT -eq 0 ] && [ $CROP_OFFSET_X -eq 0 ] && [ $CROP_OFFSET_Y -eq 0 ]; then
   mypr "Error 28: You specified a crop alignment but no crop width, height or offset."
   exit 28
fi

if [[ ( $CROP_OFFSET_X -lt 0 && $CROP_ALIGN_H -ne $CROP_ALIGN_H_CENTER ) || ( $CROP_OFFSET_Y -lt 0 && $CROP_ALIGN_V -ne $CROP_ALIGN_V_CENTER ) ]]; then
   mypr "Error 29: You specified a negative crop offset but did not ask for center alignment on that axis. Negative offsets are not allowed for left- or right-aligned crop operations."
   exit 29
fi

if [[ ( $CROP_WIDTH -eq 0 && $CROP_OFFSET_X -eq 0 && $CROP_ALIGN_H -ne $CROP_ALIGN_H_LEFT ) || ( $CROP_HEIGHT -eq 0 && $CROP_OFFSET_Y -eq 0 && $CROP_ALIGN_V -ne $CROP_ALIGN_H_LEFT ) ]]; then
   mypr "Error 30: You specified a crop alignment for an axis on which you did not specify a crop size or offset."
   exit 30
fi

if [ $OPER_CONVERT -eq 1 ] && [ -z $NEW_TYPE ]; then
   mypr "Error 31: Failed to find a file suffix after '--convert-to:'."
   exit 31
fi

if [ $OPER_CONVERT -eq 1 ] && [ $FILE_MODE -ne $FILE_MIRROR ]; then
   mypr "Error 32: You can only use file-mirroring mode ('--dest PATH') with the '--convert-to' operation. Overwrite mode and beside mode would yield confusing results if they encountered a mixture of some files that were already in the destination format and some files that needed conversion."
   exit 32
fi

## SETTINGS OUTPUT ##
echo -n ${BOLD}
myprc "--Image Manager--"
echo -n ${NORM}

if [ $DRY_RUN -eq 1 ]; then
   myprb "**This is a dry run. No files will be changed.**"
fi

if [ $SHOW_SKIPS -eq 1 ]; then
   mypr "Skipped files will be noted with the reason for the skip."
fi

myprb "Filters"

ANY_FILTER=0
if [ ! -z $SOURCE_FORMAT ]; then
   mypr "Selecting files with the suffix '$SOURCE_FORMAT'."
   ANY_FILTER=1
fi

if [ $SOURCE_WIDTH_FILTER -eq 1 ]; then
   mypr "Selecting files that are $SOURCE_WIDTH_OP_NAME${SOURCE_WIDTH_PX}px wide."
   ANY_FILTER=1
fi

if [ $SOURCE_HEIGHT_FILTER -eq 1 ]; then
   mypr "Selecting files that are $SOURCE_HEIGHT_OP_NAME${SOURCE_HEIGHT_PX}px tall."
   ANY_FILTER=1
fi

if [ $SOURCE_ORIENT_FILTER -eq 1 ]; then
   ORIENT_NAME=$SOURCE_ORIENT # "square", unless…
   if [ $SOURCE_ORIENT == "land" ]; then
      ORIENT_NAME="landscape orientation"
   elif [ $SOURCE_ORIENT == "port" ]; then
		ORIENT_NAME="portrait orientation"
	fi

   mypr "Selecting files that are $ORIENT_NAME."
   ANY_FILTER=1
fi

if [ $SOURCE_RATIO_FILTER -eq 1 ]; then
   mypr "Selecting files with aspect ratio ${SOURCE_RATIO_W}:${SOURCE_RATIO_H} (with a tolerance of ${SOURCE_RATIO_FUZZ_PERC}%)."
   ANY_FILTER=1
fi

if [ $ANY_FILTER -eq 0 ]; then
   mypr "None. All images will be selected."
fi

myprb "Operations"

if [ $OPER_PRINT -eq 1 ]; then
   mypr "The names of the selected images will be printed to screen."
fi

if [ $OPER_CROP -eq 1 ]; then
   CROP_DIM_STMT="${CROP_WIDTH}x${CROP_HEIGHT}px"
   if [ $CROP_WIDTH -eq 0 ]; then
      if [ $CROP_HEIGHT -eq 0 ]; then
         CROP_DIM_STMT=""
      else
         CROP_DIM_STMT="${CROP_HEIGHT}px tall"
      fi
   elif [ $CROP_HEIGHT -eq 0 ]; then
      CROP_DIM_STMT="${CROP_WIDTH}px wide"
   fi

   if [ $CROP_OFFSET_X -ne 0 ] || [ $CROP_OFFSET_Y -ne 0 ]; then
      CROP_DIM_STMT+=", "

      SIDE_NAME_H="left"
      if [ $CROP_ALIGN_H -eq $CROP_ALIGN_H_CENTER ]; then
         SIDE_NAME_H="horizontal center"
      elif [ $CROP_ALIGN_H -eq $CROP_ALIGN_H_RIGHT ]; then
         SIDE_NAME_H="right"
      fi

      SIDE_NAME_V="top"
      if [ $CROP_ALIGN_V -eq $CROP_ALIGN_V_CENTER ]; then
         SIDE_NAME_V="vertical center"
      elif [ $CROP_ALIGN_V -eq $CROP_ALIGN_V_BOTTOM ]; then
         SIDE_NAME_V="bottom"
      fi

      CROP_OFFSET_STMT="offset ${CROP_OFFSET_X}x${CROP_OFFSET_Y} from the origin at ${SIDE_NAME_V}-${SIDE_NAME_H}"
   fi

   mypr "The images will be cropped to ${CROP_DIM_STMT}${CROP_OFFSET_STMT}."
fi

if [ $OPER_SCALE -eq 1 ]; then
   if [ $SCALE_TYPE -eq $SCALE_WIDTH_ONLY ]; then
      mypr "The images will be proportionally scaled to make their width ${SCALE_WIDTH}px."
   elif [ $SCALE_TYPE -eq $SCALE_HEIGHT_ONLY ]; then
      mypr "The images will be proportionally scaled to make their height ${SCALE_HEIGHT}px."
   elif [ $SCALE_TYPE -eq $SCALE_WIDTH_HEIGHT ]; then
      mypr "The images will be non-proportionally scaled to ${SCALE_WIDTH}x${SCALE_HEIGHT}px."
   elif [ $SCALE_TYPE -eq $SCALE_PERCENT ]; then
      mypr "The images will be proportionally scaled to ${SCALE_PERC}% of their current size."
   fi
fi

if [ $OPER_CONVERT -eq 1 ]; then
   FORMAT=$(echo "$NEW_TYPE" | tr "[:lower:]" "[:upper:]")
   mypr "The images will be converted from their present format to $FORMAT format."
fi

if [ $OPER_LABEL -eq 1 ]; then
   mypr "The images will be named with their dimensions."
fi

myprb "File Mode"

if [ $FILE_MODE -eq $FILE_OVERWRITE ]; then
   mypr "The images in $SOURCE_DIR will be altered in place."
elif [ $FILE_MODE -eq $FILE_BESIDE ]; then
   mypr "The images in $SOURCE_DIR will be altered in place after backing up the originals."
elif [ $FILE_MODE -eq $FILE_MIRROR ]; then
   mypr "The altered images from $SOURCE_DIR will be placed in a mirrored directory inside $DEST_DIR."
   if [ $COPY_SKIPS -eq 1 ]; then
      mypr "Unaltered images will also be copied into this mirrored directory."
   fi
else
   mypr "N/A"
fi

## MAIN LOOP ##
echo -------------------------------
myprb "Processing $SOURCE_DIR..."
for FILE_REF in $(find -s "$SOURCE_DIR" -type f); do
   # If this is not a file with a name and suffix, skip it
   if [[ ! "$(basename $FILE_REF)" =~ [[:print:]]+\.[[:print:]]+$ ]]; then
      continue
   fi

   # Search for suffix in list of known image suffixes
   FILE_SUFFIX=$(trim "$FILE_REF" after last .)
   MATCHED=0
   shopt -s nocasematch
   for SUFFIX in "${IMG_SUFF[@]}"; do
      if [ "$SUFFIX" == $FILE_SUFFIX ]; then
         MATCHED=1
         break
      fi
   done

   # Override the above if a specific format was chosen as a filter
   if [ ! -z $SOURCE_FORMAT ]; then
      if [ "$SOURCE_FORMAT" == $FILE_SUFFIX ]; then
         MATCHED=1
      else
         MATCHED=0
         considerCopy "$FILE_REF"
      fi
   fi
   shopt -u nocasematch

   # If this is not an image, then don't proceed
   if [ $MATCHED -eq 0 ]; then
      continue
   fi
   
   # Get basic image info
   IMAGE_WIDTH=$(identify -format "%[fx:w]" "$FILE_REF" 2> /dev/null)
   IMAGE_HEIGHT=$(identify -format "%[fx:h]" "$FILE_REF" 2> /dev/null)
   
   if [ $? -ne 0 ]; then
		myprd "Skipping image '$FILE_REF' because the size could not be obtained; ImageMagick error $?."
		continue
	fi
	
	# Animated GIFs return wildly erroneous dimensions and have not been tested with the operations this script offers, so skip them
	if [ $FILE_SUFFIX == "gif" ]; then
		FRAME_CT=$(identify "$FILE_REF" | wc -l | tr -d ' ')
		if [ $FRAME_CT -gt 1 ]; then
			myprd "Skipping animated GIF '$FILE_REF'."
			continue
		fi
	fi
	
	# Avoid cases where image dimensions exceed 2^32, which is 10 digits long, because bash cannot handle them; it's likely that a number this large is an error, anyway
	if [ "${#IMAGE_WIDTH}" -gt 9 ] || [ "${#IMAGE_HEIGHT}" -gt 9 ]; then
	   myprd "Skipping image '$FILE_REF' because a dimension may exceed INTMAX."
	   continue
	fi

   # Apply width filter if requested
   if [ $SOURCE_WIDTH_FILTER -eq 1 ]; then
      if [ ! $IMAGE_WIDTH $SOURCE_WIDTH_OP $SOURCE_WIDTH_PX ]; then
         myprd "Skipping ${IMAGE_WIDTH}px-wide $(basename $FILE_REF) because it is not $SOURCE_WIDTH_OP_NAME${SOURCE_WIDTH_PX}px."
         considerCopy "$FILE_REF"
         continue
      fi
   fi

   # Apply height filter if requested
   if [ $SOURCE_HEIGHT_FILTER -eq 1 ]; then
      if [ ! $IMAGE_HEIGHT $SOURCE_HEIGHT_OP $SOURCE_HEIGHT_PX ]; then
         myprd "Skipping ${IMAGE_HEIGHT}px-tall $(basename $FILE_REF) because it is not $SOURCE_HEIGHT_OP_NAME${SOURCE_HEIGHT_PX}px."
         considerCopy "$FILE_REF"
         continue
      fi
   fi
   
   # Apply orientation filter if requested
   if [ $SOURCE_ORIENT_FILTER -eq 1 ]; then
      if [ $SOURCE_ORIENT == "port" ]; then
         if [ $IMAGE_WIDTH -gt $IMAGE_HEIGHT ]; then
            myprd "Skipping ${IMAGE_WIDTH}x${IMAGE_HEIGHT} $(basename $FILE_REF) because it is not portait."
            considerCopy "$FILE_REF"
            continue
         fi
      elif [ $SOURCE_ORIENT == "land" ]; then
         if [ $IMAGE_WIDTH -lt $IMAGE_HEIGHT ]; then
            myprd "Skipping ${IMAGE_WIDTH}x${IMAGE_HEIGHT} $(basename $FILE_REF) because it is not landscape."
            considerCopy "$FILE_REF"
            continue
         fi
      elif [ $SOURCE_ORIENT == "square" ]; then
         if [ $IMAGE_WIDTH -ne $IMAGE_HEIGHT ]; then
            myprd "Skipping ${IMAGE_WIDTH}x${IMAGE_HEIGHT} $(basename $FILE_REF) because it is not square."
            continue
            considerCopy "$FILE_REF"
         fi
      fi
   fi

	# Apply aspect ratio filter if requested
	if [ $SOURCE_RATIO_FILTER -eq 1 ]; then
		IMAGE_RATIO=$(echo | awk -v w=$IMAGE_WIDTH -v h=$IMAGE_HEIGHT '{printf "%f",w/h}')

		# Get abs() of diff between image's and filter's aspect ratios
		RATIO_DIFF=$(echo $IMAGE_RATIO-$SOURCE_RATIO | bc)
		if [ $(echo $RATIO_DIFF'<'0 | bc -l) -eq 1 ]; then
			RATIO_DIFF=$(echo $RATIO_DIFF'*'-1 | bc -l)
		fi

		if [ $(echo $RATIO_DIFF'>'$SOURCE_RATIO_FUZZ | bc -l) -eq 1 ]; then
         SOURCE_RATIO_LOW=$(echo | awk -v r=$SOURCE_RATIO -v f=$SOURCE_RATIO_FUZZ '{printf "%f",r-f}')
         SOURCE_RATIO_HIGH=$(echo | awk -v r=$SOURCE_RATIO -v f=$SOURCE_RATIO_FUZZ '{printf "%f",r+f}')
         myprd "Skipping ratio $IMAGE_RATIO $(basename $FILE_REF) because it is outside the range ${SOURCE_RATIO_LOW}-${SOURCE_RATIO_HIGH}."
         considerCopy "$FILE_REF"
			continue
		fi
	fi

   # If in print mode, just print file name and continue
   if [ $OPER_PRINT -eq 1 ]; then
      REL_PATH=$(trim "$FILE_REF" after first "$SOURCE_DIR/")
      echo "Found file '$REL_PATH'."
      continue
   fi

   CROP_ARG=""
   RESIZE_ARG=""

   # Construct crop operation if requested
   if [ $OPER_CROP -eq 1 ]; then
      if [ $CROP_TYPE == $CROP_WIDTH_ONLY ]; then
         CROP_ARG=" -crop ${CROP_WIDTH}x"
      elif [ $CROP_TYPE == $CROP_HEIGHT_ONLY ]; then
         CROP_ARG=" -crop x${CROP_HEIGHT}"
      elif [ $CROP_TYPE == $CROP_WIDTH_HEIGHT ]; then
         CROP_ARG=" -crop ${CROP_WIDTH}x${CROP_HEIGHT}"
      fi

      OFFSET_X=0
      if [ $CROP_ALIGN_H -eq $CROP_ALIGN_H_LEFT ]; then
         OFFSET_X=$CROP_OFFSET_X
      elif [ $CROP_ALIGN_H -eq $CROP_ALIGN_H_RIGHT ]; then
         OFFSET_X=$(($IMAGE_WIDTH-$CROP_WIDTH-$CROP_OFFSET_X))
      elif [ $CROP_ALIGN_H -eq $CROP_ALIGN_H_CENTER ]; then
         OFFSET_X=$(($IMAGE_WIDTH/2-($CROP_WIDTH/2)+$CROP_OFFSET_X))
      fi

      OFFSET_Y=0
      if [ $CROP_ALIGN_V -eq $CROP_ALIGN_V_TOP ]; then
         OFFSET_Y=$CROP_OFFSET_Y
      elif [ $CROP_ALIGN_V -eq $CROP_ALIGN_V_BOTTOM ]; then
         OFFSET_Y=$(($IMAGE_HEIGHT-$CROP_HEIGHT-$CROP_OFFSET_Y))
      elif [ $CROP_ALIGN_V -eq $CROP_ALIGN_V_CENTER ]; then
         OFFSET_Y=$(($IMAGE_HEIGHT/2-($CROP_HEIGHT/2)+$CROP_OFFSET_Y))
      fi

      CROP_ARG+="+${OFFSET_X}+${OFFSET_Y}"
   fi

   # Construct scale operation if requested
   if [ $OPER_SCALE -eq 1 ]; then
      RESIZE_ARG=" -resize"

      if [ $SCALE_TYPE -eq $SCALE_WIDTH_ONLY ]; then
         RESIZE_ARG+=" ${SCALE_WIDTH}x"
      elif [ $SCALE_TYPE -eq $SCALE_HEIGHT_ONLY ]; then
         RESIZE_ARG+=" x${SCALE_HEIGHT}"
      elif [ $SCALE_TYPE -eq $SCALE_WIDTH_HEIGHT ]; then
         RESIZE_ARG+=" ${SCALE_WIDTH}x${SCALE_HEIGHT}\\!"
      elif [ $SCALE_TYPE -eq $SCALE_PERCENT ]; then
         RESIZE_ARG+=" ${SCALE_PERC}%"
      fi
   fi

   # Assemble full call to ImageMagick
   IM_COMMAND="convert \"$FILE_REF\"${CROP_ARG}${RESIZE_ARG}"
   ALTERED_FILE_REF="$FILE_REF"
   NEW_FILE_NAME=$(basename $FILE_REF)
   if [ $FILE_MODE -eq $FILE_BESIDE ]; then
      ORIG_FILE_REF=$(trim "$FILE_REF" before last .$FILE_SUFFIX)
      ORIG_FILE_REF+="-old.$FILE_SUFFIX"
      if [ $DRY_RUN -eq 0 ]; then
         mv "$FILE_REF" "$ORIG_FILE_REF"
      else
         echo mv "$FILE_REF" "$ORIG_FILE_REF"
      fi
   elif [ $FILE_MODE -eq $FILE_MIRROR ]; then
      # Create path in new dir. equivalent to path in orig. dir.
      MIRR_PATH=$(trim "$FILE_REF" after first "$SOURCE_DIR/")
      MIRR_PATH=$(dirname "$MIRR_PATH")

      if [ $DRY_RUN -eq 0 ]; then
         if [ ! -d "$DEST_DIR/$MIRR_PATH" ]; then
            mkdir -p "$DEST_DIR/$MIRR_PATH"
         fi
      else
         echo mkdir -p "$DEST_DIR/$MIRR_PATH"
      fi

      # Prepare new file name if conversion was requested
      if [ $OPER_CONVERT -eq 1 ]; then
         CURR_SUFF=$(trim "$FILE_REF" after last .)
         NEW_FILE_NAME=$(trim "$NEW_FILE_NAME" before last .$CURR_SUFF)
         NEW_FILE_NAME+=".$NEW_TYPE"
      fi

      if [ "$MIRR_PATH" == "." ]; then
         MIRR_PATH=""
      else
         MIRR_PATH+="/"
      fi

      ALTERED_FILE_REF="$DEST_DIR/${MIRR_PATH}$NEW_FILE_NAME"
   fi
   IM_COMMAND+=" \"$ALTERED_FILE_REF\""

   # Assemble statement about operations to be performed
   declare -a OPERATION_NAMES=()
   if [ $OPER_CROP -eq 1 ]; then
      OPERATION_NAMES+=("crop")
   fi
   if [ $OPER_SCALE -eq 1 ]; then
      OPERATION_NAMES+=("scale")
   fi
   if [ $OPER_CONVERT -eq 1 ]; then
      OPERATION_NAMES+=("conversion")
   fi
   if [ $OPER_LABEL -eq 1 ]; then
      OPERATION_NAMES+=("label")
   fi
   OPERATION_STMT="Performing "
   NUM_OPS=${#OPERATION_NAMES[@]}
   if [ $NUM_OPS -gt 1 ]; then
      for ((i = 0; i < $NUM_OPS; ++i)); do
         if [ $i -lt $((NUM_OPS - 2)) ]; then
            OPERATION_STMT+="${OPERATION_NAMES[$i]}, "
         elif [ $i -lt $((NUM_OPS - 1)) ]; then
            OPERATION_STMT+="${OPERATION_NAMES[$i]} and "
         else
            OPERATION_STMT+="${OPERATION_NAMES[$i]}"
         fi
      done
   else
      OPERATION_STMT+="${OPERATION_NAMES[0]}"
   fi

   # Run ImageMagick command or else print command to terminal if in dry-run mode
   if [ $OPER_CROP -eq 1 ] || [ $OPER_CONVERT -eq 1 ] || [ $OPER_SCALE -eq 1 ]; then
      if [ $DRY_RUN -eq 0 ]; then
         mypr "$OPERATION_STMT on $(basename $FILE_REF)..."
         eval $IM_COMMAND

         # Don't keep going if we ran into an IM error
         if [ $? -ne 0 ]; then
            mypr "Exiting due to ImageMagick error $?."
            exit 99
         fi
      else
         mypr "Would have run command:"
         mypr $IM_COMMAND
      fi
   fi

   # Label file with dimensions if requested
   if [ $OPER_LABEL -eq 1 ]; then
      # If we didn't run an operation, there is no altered file; it's still back at
      # $FILE_REF or $ORIG_FILE_REF
      if [ $OPER_CROP -eq 0 ] && [ $OPER_CONVERT -eq 0 ] && [ $OPER_SCALE -eq 0 ]; then
         if [ $FILE_MODE -eq $FILE_BESIDE ]; then
            ALTERED_FILE_REF="$ORIG_FILE_REF"
         else
            ALTERED_FILE_REF="$FILE_REF"
         fi
         mypr "Labeling $(basename $FILE_REF)..."
      fi

      # Get info on the image we created
      if [ $DRY_RUN -eq 0 ]; then
         IMAGE_WIDTH=$(identify -format "%[fx:w]" "$ALTERED_FILE_REF")
         IMAGE_HEIGHT=$(identify -format "%[fx:h]" "$ALTERED_FILE_REF")
      else # we have to estimate the final size since the altered files won't exist
         if [ $OPER_CROP -eq 1 ]; then
            if [ $CROP_TYPE == $CROP_WIDTH_ONLY ] || [ $CROP_TYPE == $CROP_WIDTH_HEIGHT ]; then
               IMAGE_WIDTH=$CROP_WIDTH
            fi

            if [ $CROP_TYPE == $CROP_HEIGHT_ONLY ] || [ $CROP_TYPE == $CROP_WIDTH_HEIGHT ]; then
               IMAGE_HEIGHT=$CROP_HEIGHT
            fi
         fi
         if [ $OPER_SCALE -eq 1 ]; then
            if [ $SCALE_TYPE == $SCALE_WIDTH_ONLY ]; then
               let IMAGE_HEIGHT/=$(($IMAGE_WIDTH / $SCALE_WIDTH))
               IMAGE_WIDTH=$SCALE_WIDTH
            elif [ $SCALE_TYPE == $SCALE_HEIGHT_ONLY ]; then
               let IMAGE_WIDTH/=$(($IMAGE_HEIGHT / $SCALE_HEIGHT))
               IMAGE_HEIGHT=$SCALE_HEIGHT
            elif [ $SCALE_TYPE == $SCALE_WIDTH_HEIGHT ]; then
               IMAGE_WIDTH=$SCALE_HEIGHT
               IMAGE_HEIGHT=$SCALE_HEIGHT
            else # SCALE_PERCENT
               IMAGE_WIDTH=$(echo | awk -v w=$IMAGE_WIDTH -v p=$SCALE_PERC '{printf "%f",w*(p/100)}')
               IMAGE_WIDTH=$(round $IMAGE_WIDTH)
               IMAGE_HEIGHT=$(echo | awk -v h=$IMAGE_HEIGHT -v p=$SCALE_PERC '{printf "%f",h*(p/100)}')
               IMAGE_HEIGHT=$(round $IMAGE_HEIGHT)
            fi
         fi
      fi

      # Prepare new name
      CURR_SUFF=$(trim "$ALTERED_FILE_REF" after last .)
      LABELED_FILE_NAME=$(trim "$NEW_FILE_NAME" before last .$CURR_SUFF)
      LABELED_FILE_NAME+=" ${IMAGE_WIDTH}x${IMAGE_HEIGHT}.$CURR_SUFF"

      # If we actually ran an operation, move the file to its new name with label
      if [ $OPER_CROP -eq 1 ] || [ $OPER_CONVERT -eq 1 ] || [ $OPER_SCALE -eq 1 ]; then
         if [ $DRY_RUN -eq 0 ]; then
            mv "$ALTERED_FILE_REF" "$(dirname $ALTERED_FILE_REF)/$LABELED_FILE_NAME"
         else
            echo mv "$ALTERED_FILE_REF" "$(dirname $ALTERED_FILE_REF)/$LABELED_FILE_NAME"
         fi
      # If all we're doing is labeling the files then IM never ran, so just 'cp' or
      # 'mv' the original file depending on the file mode
      else
         if [ $DRY_RUN -eq 0 ]; then
            if [ $FILE_MODE -eq $FILE_OVERWRITE ]; then
               mv "$FILE_REF" "$(dirname $FILE_REF)/$LABELED_FILE_NAME"
            elif [ $FILE_MODE -eq $FILE_BESIDE ]; then
               cp "$ORIG_FILE_REF" "$(dirname $ORIG_FILE_REF)/$LABELED_FILE_NAME"
            elif [ $FILE_MODE -eq $FILE_MIRROR ]; then
               cp "$FILE_REF" "$DEST_DIR/${MIRR_PATH}$LABELED_FILE_NAME"
            fi
         else
            if [ $FILE_MODE -eq $FILE_OVERWRITE ]; then
               echo mv "$FILE_REF" "$(dirname $FILE_REF)/$LABELED_FILE_NAME"
            elif [ $FILE_MODE -eq $FILE_BESIDE ]; then
               echo cp "$ORIG_FILE_REF" "$(dirname $ORIG_FILE_REF)/$LABELED_FILE_NAME"
            elif [ $FILE_MODE -eq $FILE_MIRROR ]; then
               echo cp "$FILE_REF" "$DEST_DIR/${MIRR_PATH}$LABELED_FILE_NAME"
            fi
         fi
      fi
   fi
done