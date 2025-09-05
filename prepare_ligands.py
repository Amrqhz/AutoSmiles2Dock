#!/usr/bin/env python3

import os
import sys
import subprocess
import argparse

def convert_smiles_to_pdb(smiles, output_file):
    """Convert SMILES to PDB using OpenBabel"""
    cmd = f'obabel -:"{smiles}" -opdb --gen3d -O "{output_file}"'
    try:
        subprocess.run(cmd, shell=True, check=True, capture_output=True)
        return True
    except subprocess.CalledProcessError:
        return False

def convert_pdb_to_pdbqt(pdb_file, pdbqt_file):
    """Convert PDB to PDBQT using available tools"""
    # Method 1: Try prepare_ligand4.py first
    cmd = f'prepare_ligand4.py -l "{pdb_file}" -o "{pdbqt_file}" -A hydrogens -U nphs_lps'
    try:
        result = subprocess.run(cmd, shell=True, check=True, capture_output=True, text=True)
        if os.path.exists(pdbqt_file):
            return True
    except subprocess.CalledProcessError:
        pass
    
    # Method 2: Try obabel direct conversion
    cmd = f'obabel "{pdb_file}" -opdbqt -O "{pdbqt_file}" --partialcharge gasteiger'
    try:
        subprocess.run(cmd, shell=True, check=True, capture_output=True)
        if os.path.exists(pdbqt_file):
            return True
    except subprocess.CalledProcessError:
        pass
    
    # Method 3: Try pythonsh
    cmd = f'''pythonsh -c "
import sys
sys.path.append('/usr/local/lib/python2.7/site-packages/')
from AutoDockTools.MoleculePreparation import AD4LigandPreparation
prep = AD4LigandPreparation()
prep.prepare_ligand('{pdb_file}', outputfilename='{pdbqt_file}', repairs='checkhydrogens', charges_to_add='gasteiger')
"'''
    try:
        subprocess.run(cmd, shell=True, check=True, capture_output=True)
        if os.path.exists(pdbqt_file):
            return True
    except subprocess.CalledProcessError:
        pass
    
    return False

def reposition_ligand(input_file, output_file, target_x, target_y, target_z):
    """Reposition ligand to be centered near target coordinates"""
    try:
        with open(input_file, 'r') as f:
            lines = f.readlines()
        
        # Find all atom coordinates
        coords = []
        atom_line_indices = []
        
        for i, line in enumerate(lines):
            if line.startswith('HETATM') or line.startswith('ATOM'):
                atom_line_indices.append(i)
                x = float(line[30:38])
                y = float(line[38:46])
                z = float(line[46:54])
                coords.append([x, y, z])
        
        if not coords:
            return False
        
        # Calculate current center of mass
        center_x = sum(coord[0] for coord in coords) / len(coords)
        center_y = sum(coord[1] for coord in coords) / len(coords)
        center_z = sum(coord[2] for coord in coords) / len(coords)
        
        # Calculate translation needed
        trans_x = target_x - center_x
        trans_y = target_y - center_y
        trans_z = target_z - center_z
        
        # Apply translation to all atom lines
        for line_idx in atom_line_indices:
            line = lines[line_idx]
            x = float(line[30:38]) + trans_x
            y = float(line[38:46]) + trans_y
            z = float(line[46:54]) + trans_z
            
            # Replace coordinates in the line (maintaining PDB format)
            new_line = line[:30] + f'{x:8.3f}' + f'{y:8.3f}' + f'{z:8.3f}' + line[54:]
            lines[line_idx] = new_line
        
        # Write repositioned file
        with open(output_file, 'w') as f:
            f.writelines(lines)
        
        return True
        
    except Exception as e:
        print(f"Error repositioning {input_file}: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(description='Prepare multiple ligands from SMILES for AutoDock')
    parser.add_argument('smiles_file', help='File containing SMILES strings (one per line, optionally with names)')
    parser.add_argument('grid_x', type=float, help='Grid center X coordinate')
    parser.add_argument('grid_y', type=float, help='Grid center Y coordinate') 
    parser.add_argument('grid_z', type=float, help='Grid center Z coordinate')
    parser.add_argument('--output_dir', default='prepared_ligands', help='Output directory for processed ligands')
    
    args = parser.parse_args()
    
    # Create output directories
    os.makedirs(f"{args.output_dir}/pdb", exist_ok=True)
    os.makedirs(f"{args.output_dir}/pdbqt", exist_ok=True)
    os.makedirs(f"{args.output_dir}/positioned", exist_ok=True)
    
    print(f"Processing ligands with grid center: {args.grid_x}, {args.grid_y}, {args.grid_z}")
    print("="*60)
    
    success_count = 0
    total_count = 0
    
    with open(args.smiles_file, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            
            # Skip empty lines and comments
            if not line or line.startswith('#'):
                continue
            
            # Parse SMILES and optional name
            parts = line.split()
            smiles = parts[0]
            name = parts[1] if len(parts) > 1 else f"ligand_{line_num}"
            
            total_count += 1
            print(f"Processing {total_count}: {name}")
            
            # Step 1: SMILES to PDB
            pdb_file = f"{args.output_dir}/pdb/{name}.pdb"
            print(f"  Converting SMILES to PDB...")
            if not convert_smiles_to_pdb(smiles, pdb_file):
                print(f"  ✗ Failed to convert SMILES to PDB")
                continue
            
            # Step 2: PDB to PDBQT
            pdbqt_file = f"{args.output_dir}/pdbqt/{name}.pdbqt"
            print(f"  Converting PDB to PDBQT...")
            if not convert_pdb_to_pdbqt(pdb_file, pdbqt_file):
                print(f"  ✗ Failed to convert PDB to PDBQT")
                continue
            
            # Step 3: Reposition near binding site
            positioned_file = f"{args.output_dir}/positioned/{name}.pdbqt"
            print(f"  Repositioning near binding site...")
            if not reposition_ligand(pdbqt_file, positioned_file, args.grid_x, args.grid_y, args.grid_z):
                print(f"  ✗ Failed to reposition ligand")
                continue
            
            print(f"  ✓ Successfully processed {name}")
            success_count += 1
            print()
    
    print("="*60)
    print(f"Processing complete: {success_count}/{total_count} ligands successfully prepared")
    print(f"Positioned PDBQT files are in: {args.output_dir}/positioned/")
    print()
    print("Now you can dock each ligand:")
    print(f"for ligand in {args.output_dir}/positioned/*.pdbqt; do")
    print("    cp \"$ligand\" l.pdbqt")
    print("    rm r.dlg r.glg 2>/dev/null")
    print("    autogrid4 -p r.gpf -l r.glg")
    print("    autodock4 -p r.dpf -l r.dlg")
    print("    # Process results and rename output files")
    print("done")

if __name__ == "__main__":
    main()
