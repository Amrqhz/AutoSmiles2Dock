#!/bin/bash

# Script to dock all prepared ligands
# Usage: ./dock_all_ligands.sh

# Check if positioned ligands directory exists
if [ ! -d "prepared_ligands/positioned" ]; then
    echo "Error: prepared_ligands/positioned directory not found!"
    echo "Run the ligand preparation script first."
    exit 1
fi

# Check if required AutoDock files exist
if [ ! -f "r.gpf" ] || [ ! -f "r.dpf" ]; then
    echo "Error: r.gpf or r.dpf files not found!"
    echo "Make sure your AutoDock parameter files are in the current directory."
    exit 1
fi

# Create results directory
mkdir -p docking_results

echo "Starting automated docking..."
echo "=============================="

# Counter for progress
count=0
total=$(ls prepared_ligands/positioned/*.pdbqt 2>/dev/null | wc -l)

if [ $total -eq 0 ]; then
    echo "No PDBQT files found in prepared_ligands/positioned/"
    exit 1
fi

echo "Found $total ligands to dock"
echo ""

# Loop through all positioned ligands
for ligand_file in prepared_ligands/positioned/*.pdbqt; do
    # Get ligand name without path and extension
    ligand_name=$(basename "$ligand_file" .pdbqt)
    
    ((count++))
    echo "[$count/$total] Processing: $ligand_name"
    
    # Copy ligand to working directory as l.pdbqt
    cp "$ligand_file" l.pdbqt
    
    # Clean up previous results
    rm -f r.dlg r.glg 2>/dev/null
    
    echo "  Running AutoGrid..."
    # Generate grid maps
    autogrid4 -p r.gpf -l r.glg
    
    if [ $? -ne 0 ]; then
        echo "  ✗ AutoGrid failed for $ligand_name"
        continue
    fi
    
    echo "  Running AutoDock..."
    # Run docking
    autodock4 -p r.dpf -l r.dlg
    
    if [ $? -ne 0 ]; then
        echo "  ✗ AutoDock failed for $ligand_name"
        continue
    fi
    
    # Move results to organized directory
    if [ -f "r.dlg" ]; then
        cp r.dlg "docking_results/${ligand_name}.dlg"
        echo "  ✓ Successfully docked $ligand_name"
        
        # Extract best pose binding energy (optional)
        best_energy=$(grep "DOCKED: USER    Estimated Free Energy of Binding" r.dlg | head -1 | awk '{print $8}')
        if [ ! -z "$best_energy" ]; then
            echo "  Best binding energy: $best_energy kcal/mol"
        fi
    else
        echo "  ✗ No results file generated for $ligand_name"
    fi
    
    # Clean up grid files to save space (optional)
    rm -f r.*.map r.e.map r.d.map 2>/dev/null
    
    echo ""
done

echo "=============================="
echo "Docking complete!"
echo "Results are saved in: docking_results/"
echo ""
echo "To analyze results:"
echo "ls -la docking_results/"
echo ""
echo "To extract binding energies:"
echo "grep 'Estimated Free Energy of Binding' docking_results/*.dlg | head -20"
