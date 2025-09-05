#!/bin/bash

# Script to automate ligand preparation from SMILES for AutoDock
# Usage: ./automate_ligand_preparation.sh smiles_file.txt grid_center_x grid_center_y grid_center_z

# Check if correct number of arguments
if [ $# -ne 4 ]; then
    echo "Usage: $0 <smiles_file> <grid_center_x> <grid_center_y> <grid_center_z>"
    echo "Example: $0 smiles.txt 16.097 15.334 50.085"
    exit 1
fi

SMILES_FILE=$1
GRID_X=$2
GRID_Y=$3
GRID_Z=$4

# Check if files exist
if [ ! -f "$SMILES_FILE" ]; then
    echo "Error: SMILES file $SMILES_FILE not found!"
    exit 1
fi

# Create output directories
mkdir -p ligands_pdb ligands_pdbqt ligands_positioned

echo "Processing ligands with grid center: $GRID_X, $GRID_Y, $GRID_Z"
echo "=========================================="

# Counter for ligands
counter=1

# Read SMILES file line by line
while IFS= read -r line; do
    # Skip empty lines and comments
    if [[ -z "$line" || "$line" == \#* ]]; then
        continue
    fi
    
    # Extract SMILES and name (if provided)
    # Format can be: "SMILES" or "SMILES name"
    smiles=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | awk '{print $2}')
    
    # If no name provided, use ligand_N
    if [[ -z "$name" ]]; then
        name="ligand_${counter}"
    fi
    
    echo "Processing: $name ($smiles)"
    
    # Step 1: Convert SMILES to PDB using OpenBabel
    echo "  Converting SMILES to PDB..."
    obabel -:"$smiles" -opdb --gen3d -O "ligands_pdb/${name}.pdb" 2>/dev/null
    
    if [ ! -f "ligands_pdb/${name}.pdb" ]; then
        echo "  Error: Failed to generate PDB for $name"
        ((counter++))
        continue
    fi
    
    # Step 2: Convert PDB to PDBQT using AutoDock Tools
    echo "  Converting PDB to PDBQT..."
    pythonsh -c "
import sys
sys.path.append('/usr/local/lib/python2.7/site-packages/')
from AutoDockTools.MoleculePreparation import AD4LigandPreparation
prep = AD4LigandPreparation()
prep.prepare_ligand('ligands_pdb/${name}.pdb', outputfilename='ligands_pdbqt/${name}.pdbqt', repairs='checkhydrogens', charges_to_add='gasteiger')
" 2>/dev/null
    
    # Alternative method if above doesn't work (using prepare_ligand4.py directly)
    if [ ! -f "ligands_pdbqt/${name}.pdbqt" ]; then
        prepare_ligand4.py -l "ligands_pdb/${name}.pdb" -o "ligands_pdbqt/${name}.pdbqt" -A hydrogens -U nphs_lps 2>/dev/null
    fi
    
    if [ ! -f "ligands_pdbqt/${name}.pdbqt" ]; then
        echo "  Error: Failed to generate PDBQT for $name"
        ((counter++))
        continue
    fi
    
    # Step 3: Reposition ligand near grid center
    echo "  Repositioning ligand near binding site..."
    python3 -c "
import sys

def reposition_ligand(input_file, output_file, target_x, target_y, target_z):
    with open(input_file, 'r') as f:
        lines = f.readlines()
    
    # Find current center of mass
    coords = []
    atom_lines = []
    for i, line in enumerate(lines):
        if line.startswith('HETATM') or line.startswith('ATOM'):
            atom_lines.append(i)
            x = float(line[30:38])
            y = float(line[38:46])
            z = float(line[46:54])
            coords.append([x, y, z])
    
    if not coords:
        print('No atoms found')
        return False
    
    # Calculate current center
    center_x = sum(coord[0] for coord in coords) / len(coords)
    center_y = sum(coord[1] for coord in coords) / len(coords)
    center_z = sum(coord[2] for coord in coords) / len(coords)
    
    # Calculate translation needed
    trans_x = target_x - center_x
    trans_y = target_y - center_y
    trans_z = target_z - center_z
    
    # Apply translation
    for line_idx in atom_lines:
        line = lines[line_idx]
        x = float(line[30:38]) + trans_x
        y = float(line[38:46]) + trans_y
        z = float(line[46:54]) + trans_z
        
        # Replace coordinates in the line
        new_line = line[:30] + f'{x:8.3f}' + f'{y:8.3f}' + f'{z:8.3f}' + line[54:]
        lines[line_idx] = new_line
    
    # Write repositioned file
    with open(output_file, 'w') as f:
        f.writelines(lines)
    
    return True

# Reposition the ligand
success = reposition_ligand('ligands_pdbqt/${name}.pdbqt', 'ligands_positioned/${name}.pdbqt', $GRID_X, $GRID_Y, $GRID_Z)
if success:
    print('  Successfully repositioned')
else:
    print('  Error in repositioning')
"
    
    if [ -f "ligands_positioned/${name}.pdbqt" ]; then
        echo "  ✓ Successfully processed $name"
    else
        echo "  ✗ Failed to process $name"
    fi
    
    echo ""
    ((counter++))
    
done < "$SMILES_FILE"

echo "Processing complete!"
echo "Positioned PDBQT files are in: ligands_positioned/"
echo ""
echo "Now you can dock each ligand using:"
echo "for ligand in ligands_positioned/*.pdbqt; do"
echo "    cp \"\$ligand\" l.pdbqt"
echo "    rm r.dlg r.glg 2>/dev/null"
echo "    autogrid4 -p r.gpf -l r.glg"
echo "    autodock4 -p r.dpf -l r.dlg"
echo "    # Process results..."
echo "done"
