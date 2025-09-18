#!/bin/bash

# Extract Best Binding Poses from AutoDock Results - CORRECTED VERSION
# This script analyzes .dlg files and extracts the best binding pose for each ligand
# Usage: ./extract_best_poses.sh [options]

# Default settings
RESULTS_DIR="docking_results"
OUTPUT_DIR="best_poses"
ENERGY_CUTOFF=-5.0
MIN_CLUSTER_SIZE=1
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --results-dir)
            RESULTS_DIR="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --energy-cutoff)
            ENERGY_CUTOFF="$2"
            shift 2
            ;;
        --cluster-size)
            MIN_CLUSTER_SIZE="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --results-dir DIR   : Directory containing .dlg files (default: docking_results)"
            echo "  --output-dir DIR    : Directory to save extracted poses (default: best_poses)"
            echo "  --energy-cutoff NUM : Only extract poses with energy better than cutoff (default: -5.0)"
            echo "  --cluster-size NUM  : Minimum cluster size to consider (default: 1)"
            echo "  --verbose          : Show detailed analysis for each ligand"
            echo "  -h, --help         : Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "${CYAN}$1${NC}"; }

# Function to extract best pose from clustering analysis at end of DLG file
extract_best_pose() {
    local dlg_file=$1
    local ligand_name=$(basename "$dlg_file" .dlg)
    local output_file="$OUTPUT_DIR/run_${ligand_name}.pdb"
    
    if [ ! -f "$dlg_file" ]; then
        print_error "DLG file not found: $dlg_file"
        return 1
    fi
    
    print_status "Processing: $ligand_name"
    
    # First, try to find the clustering analysis section
    if grep -q "LOWEST ENERGY DOCKED CONFORMATION from EACH CLUSTER" "$dlg_file"; then
        if extract_best_pose_from_clustering "$dlg_file" "$ligand_name" "$output_file"; then
            return 0
        fi
    fi
    
    # If clustering fails, try individual runs
    extract_best_pose_from_runs "$dlg_file" "$ligand_name" "$output_file"
    return $?
}
# Function to extract from clustering analysis
extract_best_pose_from_clustering() {
    local dlg_file=$1
    local ligand_name=$2
    local output_file=$3
    
    # Extract best energy and run info from clustering section
    local cluster_info=$(awk '
        /LOWEST ENERGY DOCKED CONFORMATION from EACH CLUSTER/,/TER/ {
            if (/USER    Estimated Free Energy of Binding/) {
                match($0, /= *(-?[0-9]+\.?[0-9]*)/)
                if (RSTART > 0) {
                    energy = substr($0, RSTART+1, RLENGTH-1)
                    gsub(/^[ ]*/, "", energy)
                }
            }
            if (/USER    Run = /) {
                run = $4
            }
            if (/USER    Number of conformations in this cluster/) {
                cluster_size = $9
            }
        }
        END {
            if (energy && run && cluster_size) {
                print energy, run, cluster_size
            }
        }
    ' "$dlg_file")
    
    if [ -z "$cluster_info" ]; then
        return 1
    fi
    
    local best_energy=$(echo "$cluster_info" | awk '{print $1}')
    local best_run=$(echo "$cluster_info" | awk '{print $2}')
    local cluster_size=$(echo "$cluster_info" | awk '{print $3}')
    
    if [ "$VERBOSE" = true ]; then
        echo "    📊 Best energy: $best_energy kcal/mol (Run $best_run)"
        echo "    🎯 Cluster size: $cluster_size conformations"
    fi
    
    # Check if energy meets cutoff criteria
    local meets_cutoff=$(echo "$best_energy $ENERGY_CUTOFF" | awk '{if ($1 <= $2) print "1"; else print "0"}')
    if [ "$meets_cutoff" = "0" ]; then
        print_warning "$ligand_name: Best energy ($best_energy) doesn't meet cutoff ($ENERGY_CUTOFF)"
        if [ "$VERBOSE" = false ]; then
            return 1
        fi
    fi
    
    # Extract the coordinates from the clustering section
    awk '
        /LOWEST ENERGY DOCKED CONFORMATION from EACH CLUSTER/,/TER/ {
            if (/^ATOM/ || /^HETATM/) {
                print $0
            }
            if (/^TER/) {
                print "TER"
                print "ENDMDL"
                exit
            }
        }
    ' "$dlg_file" > "$output_file"
    
    # Verify and add metadata
    if [ -f "$output_file" ] && [ -s "$output_file" ]; then
        local temp_file=$(mktemp)
        {
            echo "HEADER    Best docking pose for $ligand_name"
            echo "HEADER    Binding Energy: $best_energy kcal/mol"
            echo "HEADER    Run Number: $best_run"
            echo "HEADER    Cluster Size: $cluster_size"
            echo "HEADER    Extracted on: $(date)"
            cat "$output_file"
        } > "$temp_file"
        mv "$temp_file" "$output_file"
        
        print_success "$ligand_name: Extracted best pose (Energy: $best_energy kcal/mol)"
        return 0
    else
        return 1
    fi
}




# Fallback function to extract from individual runs if clustering analysis not found
extract_best_pose_from_runs() {
    local dlg_file=$1
    local ligand_name=$2
    local output_file=$3
    
    print_warning "$ligand_name: No clustering analysis found, trying individual run analysis"
    
    # Find the run with the best (lowest) binding energy - try multiple patterns
    local best_info=$(awk '
        BEGIN { best_energy = 999999; best_run = "" }
        
        /^DOCKED: USER    Run = / || /USER    Run = / { 
            run = $NF
            gsub(/[^0-9]/, "", run)  # Keep only digits
        }
        
        /Estimated Free Energy of Binding/ {
            # Try multiple patterns to extract energy
            if (match($0, /= *(-?[0-9]+\.?[0-9]*)/)) {
                energy = substr($0, RSTART+1, RLENGTH-1)
                gsub(/^[ ]*/, "", energy)
                energy = energy + 0  # Convert to number
                if (energy < best_energy && run != "") {
                    best_energy = energy
                    best_run = run
                }
            }
        }
        
        END { 
            if (best_run != "" && best_energy < 999999) {
                print best_energy, best_run
            }
        }
    ' "$dlg_file")
    
    if [ -z "$best_info" ]; then
        print_warning "$ligand_name: No binding energies found in file"
        return 1
    fi
    
    local best_energy=$(echo "$best_info" | awk '{print $1}')
    local best_run=$(echo "$best_info" | awk '{print $2}')
    
    if [ "$VERBOSE" = true ]; then
        echo "    📊 Best energy: $best_energy kcal/mol (Run $best_run)"
        echo "    🎯 Extracted from individual runs (no clustering)"
    fi
    
    # Check if energy meets cutoff criteria
    local meets_cutoff=$(echo "$best_energy $ENERGY_CUTOFF" | awk '{if ($1 <= $2) print "1"; else print "0"}')
    if [ "$meets_cutoff" = "0" ]; then
        print_warning "$ligand_name: Best energy ($best_energy) doesn't meet cutoff ($ENERGY_CUTOFF)"
        if [ "$VERBOSE" = false ]; then
            return 1
        fi
    fi
    
    # Extract the coordinates for the best run - try multiple extraction patterns
    local extracted=false
    
    # Method 1: Look for "DOCKED: MODEL" followed by run number
    awk -v target_run="$best_run" '
        BEGIN { extracting = 0; found_model = 0 }
        
        /^DOCKED: USER    Run = / || /USER    Run = / {
            run = $NF
            gsub(/[^0-9]/, "", run)
            if (run == target_run) {
                extracting = 1
                found_model = 0
            } else {
                extracting = 0
                found_model = 0
            }
        }
        
        extracting && (/^DOCKED: MODEL/ || /^MODEL/) {
            found_model = 1
            next
        }
        
        extracting && found_model && (/^DOCKED: ATOM/ || /^DOCKED: HETATM/ || /^ATOM/ || /^HETATM/) {
            line = $0
            gsub(/^DOCKED: /, "", line)  # Remove DOCKED prefix if present
            if (line ~ /^(ATOM|HETATM)/) {
                print line
            }
        }
        
        extracting && found_model && (/^DOCKED: TER/ || /^TER/) {
            print "TER"
            print "ENDMDL"
            exit
        }
        
        extracting && found_model && /^DOCKED: ENDMDL/ {
            print "ENDMDL"
            exit
        }
    ' "$dlg_file" > "$output_file"
    
    # Check if we got coordinates
    if [ -f "$output_file" ] && [ -s "$output_file" ] && grep -q "^ATOM\|^HETATM" "$output_file"; then
        extracted=true
    else
        # Method 2: Try extracting from any run section with matching energy
        awk -v target_energy="$best_energy" '
            /Estimated Free Energy of Binding/ {
                if (match($0, /= *(-?[0-9]+\.?[0-9]*)/)) {
                    energy = substr($0, RSTART+1, RLENGTH-1)
                    gsub(/^[ ]*/, "", energy)
                    energy = energy + 0
                    if (energy == target_energy) {
                        extracting = 1
                        found_coords = 0
                    }
                }
            }
            
            extracting && (/^DOCKED: ATOM/ || /^DOCKED: HETATM/ || /^ATOM/ || /^HETATM/) && !found_coords {
                found_coords = 1
                coords_section = 1
            }
            
            coords_section && (/^DOCKED: ATOM/ || /^DOCKED: HETATM/ || /^ATOM/ || /^HETATM/) {
                line = $0
                gsub(/^DOCKED: /, "", line)
                if (line ~ /^(ATOM|HETATM)/) {
                    print line
                }
            }
            
            coords_section && (/^DOCKED: TER/ || /^TER/ || /^DOCKED: ENDMDL/ || /^ENDMDL/) {
                if (/TER/) print "TER"
                print "ENDMDL"
                exit
            }
        ' "$dlg_file" > "$output_file"
        
        if [ -f "$output_file" ] && [ -s "$output_file" ] && grep -q "^ATOM\|^HETATM" "$output_file"; then
            extracted=true
        fi
    fi
    
    # Verify output and add metadata
    if [ "$extracted" = true ]; then
        local temp_file=$(mktemp)
        {
            echo "HEADER    Best docking pose for $ligand_name"
            echo "HEADER    Binding Energy: $best_energy kcal/mol"
            echo "HEADER    Run Number: $best_run"
            echo "HEADER    Extracted from: Individual runs analysis"
            echo "HEADER    Extracted on: $(date)"
            cat "$output_file"
        } > "$temp_file"
        mv "$temp_file" "$output_file"
        
        print_success "$ligand_name: Extracted best pose from runs (Energy: $best_energy kcal/mol)"
        return 0
    else
        print_error "$ligand_name: Failed to extract pose coordinates from runs"
        rm -f "$output_file" 2>/dev/null
        return 1
    fi
}

# Function to create summary of extracted poses
create_extraction_summary() {
    local summary_file="$OUTPUT_DIR/EXTRACTION_SUMMARY.txt"
    
    print_status "Creating extraction summary..."
    
    echo "BEST BINDING POSES EXTRACTION SUMMARY" > "$summary_file"
    echo "Generated on: $(date)" >> "$summary_file"
    echo "Extraction criteria:" >> "$summary_file"
    echo "  - Energy cutoff: $ENERGY_CUTOFF kcal/mol" >> "$summary_file"
    echo "  - Minimum cluster size: $MIN_CLUSTER_SIZE" >> "$summary_file"
    echo "=========================================" >> "$summary_file"
    echo "" >> "$summary_file"
    
    # Table header
    printf "%-25s | %-15s | %-10s | %-15s\n" "Ligand Name" "Best Energy" "Run #" "Status" >> "$summary_file"
    echo "------------------------------------------------------------------------" >> "$summary_file"
    
    # Process each extracted PDB file
    for pdb_file in "$OUTPUT_DIR"/run_*.pdb; do
        if [ -f "$pdb_file" ]; then
            local ligand_name=$(basename "$pdb_file" | sed 's/^run_//' | sed 's/\.pdb$//')
            
            # Extract metadata from file header
            local best_energy=$(grep "HEADER.*Binding Energy:" "$pdb_file" | sed 's/.*Binding Energy: *//' | awk '{print $1}')
            local run_number=$(grep "HEADER.*Run Number:" "$pdb_file" | sed 's/.*Run Number: *//' | awk '{print $1}')
            
            [ -z "$best_energy" ] && best_energy="N/A"
            [ -z "$run_number" ] && run_number="N/A"
            
            # Determine status
            local status="EXTRACTED"
            if [ "$best_energy" != "N/A" ]; then
                local meets_cutoff=$(echo "$best_energy $ENERGY_CUTOFF" | awk '{if ($1 <= $2) print "1"; else print "0"}')
                if [ "$meets_cutoff" = "0" ]; then
                    status="WEAK BINDING"
                fi
            fi
            
            printf "%-25s | %-15s | %-10s | %-15s\n" "$ligand_name" "$best_energy" "$run_number" "$status" >> "$summary_file"
        fi
    done
    
    echo "" >> "$summary_file"
    echo "Legend:" >> "$summary_file"
    echo "EXTRACTED    - Pose successfully extracted" >> "$summary_file"
    echo "WEAK BINDING - Energy worse than cutoff but still extracted" >> "$summary_file"
    echo "" >> "$summary_file"
    echo "Output files are in PDB format: run_<ligand_name>.pdb" >> "$summary_file"
    
    print_success "Extraction summary created: $summary_file"
}

# Main script starts here
clear
print_header "╔══════════════════════════════════════════════════════════╗"
print_header "║           🧬 BEST BINDING POSES EXTRACTOR 🧬            ║"
print_header "║         From AutoDock DLG Results - CORRECTED           ║"
print_header "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check if results directory exists
if [ ! -d "$RESULTS_DIR" ]; then
    print_error "Results directory not found: $RESULTS_DIR"
    print_status "Run the docking script first or specify correct directory with --results-dir"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Count DLG files
total_files=$(ls "$RESULTS_DIR"/*.dlg 2>/dev/null | wc -l)

if [ $total_files -eq 0 ]; then
    print_error "No .dlg files found in $RESULTS_DIR/"
    exit 1
fi

print_status "Found $total_files DLG files to process"
print_status "Energy cutoff: $ENERGY_CUTOFF kcal/mol"
print_status "Minimum cluster size: $MIN_CLUSTER_SIZE"
print_status "Output directory: $OUTPUT_DIR"
if [ "$VERBOSE" = true ]; then
    print_status "Verbose mode: ON"
fi
echo ""

# Record start time
start_time=$(date +%s)

# Process each DLG file
success_count=0
processed_count=0

for dlg_file in "$RESULTS_DIR"/*.dlg; do
    if [ -f "$dlg_file" ]; then
        ((processed_count++))
        echo -e "\n${CYAN}[$processed_count/$total_files]${NC}"
        
        if extract_best_pose "$dlg_file"; then
            ((success_count++))
        fi
    fi
done

# Calculate total time
end_time=$(date +%s)
total_time=$((end_time - start_time))
minutes=$((total_time / 60))
seconds=$((total_time % 60))

print_header "\n╔══════════════════════════════════════════════════════════╗"
print_header "║                  🎉 EXTRACTION COMPLETE! 🎉              ║"
print_header "╚══════════════════════════════════════════════════════════╝"

print_success "Successfully extracted: $success_count/$processed_count poses"
print_success "Processing time: ${minutes}m ${seconds}s"
print_success "Results saved in: $OUTPUT_DIR/"

# Create summary report
create_extraction_summary

print_header "\n📁 RESULTS LOCATION:"
echo "  📋 Extracted poses: $OUTPUT_DIR/run_*.pdb"
echo "  📄 Summary report: $OUTPUT_DIR/EXTRACTION_SUMMARY.txt"

print_header "\n🔍 QUICK COMMANDS:"
echo -e "View summary:        ${CYAN}cat $OUTPUT_DIR/EXTRACTION_SUMMARY.txt${NC}"
echo -e "Count extracted:     ${CYAN}ls $OUTPUT_DIR/run_*.pdb | wc -l${NC}"
echo -e "List all poses:      ${CYAN}ls -la $OUTPUT_DIR/run_*.pdb${NC}"

print_header "\n✨ Best binding poses extracted and ready for visualization!"
echo ""