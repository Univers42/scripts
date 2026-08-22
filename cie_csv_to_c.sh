#!/bin/sh
# **************************************************************************** #
#                                                                              #
#    cie_csv_to_c.sh                                                           #
#                                                                              #
#    Converts CIE 1931 CSV data to C source files.                             #
#    Input:  value.csv (wavelength, x_bar, y_bar, z_bar)                       #
#    Output: cie_table.c + cie_table.h                                         #
#                                                                              #
#    Usage: ./cie_csv_to_c.sh <input.csv> <output_dir>                         #
#                                                                              #
# **************************************************************************** #

set -e

CSV="$1"
OUTDIR="$2"

if [ -z "$CSV" ] || [ -z "$OUTDIR" ]; then
	echo "Usage: $0 <input.csv> <output_dir>" >&2
	exit 1
fi

if [ ! -f "$CSV" ]; then
	echo "Error: CSV file not found: $CSV" >&2
	exit 1
fi

mkdir -p "$OUTDIR"

HEADER="$OUTDIR/cie_table.h"
SOURCE="$OUTDIR/cie_table.c"

# --------------------------------------------------------------------------- #
#  Generate header                                                             #
# --------------------------------------------------------------------------- #

cat > "$HEADER" << 'HEADER_EOF'
/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   cie_table.h                                        :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: codegen (cie_csv_to_c.sh)                  +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2026/03/09 00:00:00 by codegen           #+#    #+#             */
/*   Updated: 2026/03/09 00:00:00 by codegen           ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#ifndef CIE_TABLE_H
# define CIE_TABLE_H

# define CIE_SAMPLES		471
# define CIE_LAMBDA_MIN		360
# define CIE_LAMBDA_MAX		830
# define CIE_LAMBDA_STEP	1

typedef struct s_cie_table
{
	const float	*x;
	const float	*y;
	const float	*z;
	int			count;
	int			lambda_min;
	int			lambda_step;
}	t_cie_table;

t_cie_table	cie_get_table(void);

#endif
HEADER_EOF

# --------------------------------------------------------------------------- #
#  Generate source                                                             #
# --------------------------------------------------------------------------- #

cat > "$SOURCE" << 'SOURCE_HEADER'
/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   cie_table.c                                        :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: codegen (cie_csv_to_c.sh)                  +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2026/03/09 00:00:00 by codegen           #+#    #+#             */
/*   Updated: 2026/03/09 00:00:00 by codegen           ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "cie_table.h"

SOURCE_HEADER

# Generate x_bar array
printf 'static const float\tg_cie_x[CIE_SAMPLES] = {\n' >> "$SOURCE"
awk -F',' '{ printf "\t%sf,\n", $2 }' "$CSV" >> "$SOURCE"
printf '};\n\n' >> "$SOURCE"

# Generate y_bar array
printf 'static const float\tg_cie_y[CIE_SAMPLES] = {\n' >> "$SOURCE"
awk -F',' '{ printf "\t%sf,\n", $3 }' "$CSV" >> "$SOURCE"
printf '};\n\n' >> "$SOURCE"

# Generate z_bar array
printf 'static const float\tg_cie_z[CIE_SAMPLES] = {\n' >> "$SOURCE"
awk -F',' '{ printf "\t%sf,\n", $4 }' "$CSV" >> "$SOURCE"
printf '};\n\n' >> "$SOURCE"

# Generate accessor
cat >> "$SOURCE" << 'SOURCE_FOOTER'
t_cie_table	cie_get_table(void)
{
	t_cie_table	tbl;

	tbl.x = g_cie_x;
	tbl.y = g_cie_y;
	tbl.z = g_cie_z;
	tbl.count = CIE_SAMPLES;
	tbl.lambda_min = CIE_LAMBDA_MIN;
	tbl.lambda_step = CIE_LAMBDA_STEP;
	return (tbl);
}
SOURCE_FOOTER

echo "Generated: $HEADER"
echo "Generated: $SOURCE"
