#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_OUTLINE_H
/* FT_Load_Sfnt_Table — lets the Linux backend pull the raw 'MATH' table out of
   a font, which is what MathTableParser expects (the Apple path uses
   CGFont.table(for:)). */
#include FT_TRUETYPE_TABLES_H
