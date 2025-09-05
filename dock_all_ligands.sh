#!/bin/bash

# Enhanced AutoDock Automation Script with Analysis - FIXED VERSION
# Usage: ./dock_all_ligands.sh [options]
# Options:
#   --parallel N    : Run N docking jobs in parallel (default: 1)
#   --keep-maps    : Keep grid map files (saves time for multiple ligands)
#   --no-analysis  : Skip detailed analysis

# Default settings
PARALLEL_JOBS=1
KEEP_MAPS=false
SKIP_ANALYSIS=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --parallel)
            PARALLEL_JOBS="$2"
            shift 2
            ;;
        --keep-maps)
            KEEP_MAPS=true
            shift
            ;;
        --no-analysis)
            SKIP_ANALYSIS=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --parallel N   : Run N docking jobs in parallel"
            echo "  --keep-maps   : Keep grid map files (faster for multiple ligands)"
            echo "  --no-analysis : Skip detailed analysis"
            echo "  -h, --help    : Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${CREAM}$1${NC}"
}

# Function to extract and display cluster information
analyze_docking_results() {
    local dlg_file=$1
    local ligand_name=$2
    
    if [ ! -f "$dlg_file" ]; then
        print_error "Results file not found: $dlg_file"
        return 1
    fi
    
    # Extract cluster information
    echo -e "\n${CYAN}=== DOCKING ANALYSIS FOR $ligand_name ===${NC}"
    
    # Best binding energy - Fixed regex pattern
    best_energy=$(grep "DOCKED: USER    Estimated Free Energy of Binding" "$dlg_file" | head -1 | awk '{print $9}' | sed 's/=//g')
    if [ ! -z "$best_energy" ] && [ "$best_energy" != "" ]; then
        echo -e "🎯 ${GREEN}Best Binding Energy: $best_energy kcal/mol${NC}"
    else
        # Alternative extraction method
        best_energy=$(grep "Estimated Free Energy of Binding" "$dlg_file" | head -1 | awk -F'=' '{print $2}' | awk '{print $1}')
        if [ ! -z "$best_energy" ] && [ "$best_energy" != "" ]; then
            echo -e "🎯 ${GREEN}Best Binding Energy: $best_energy kcal/mol${NC}"
        else
            print_warning "Could not extract binding energy"
        fi
    fi
    
    # Extract cluster histogram
    echo -e "\n📊 ${YELLOW}CLUSTER ANALYSIS:${NC}"
    
    # Look for cluster information in the DLG file
    if grep -q "CLUSTERING HISTOGRAM" "$dlg_file"; then
        echo "   Cluster | Members | Lowest Energy | Mean Energy | Reference RMS"
        echo "   --------|---------|---------------|-------------|---------------"
        
        # Extract cluster data (between CLUSTERING HISTOGRAM and next section)
        awk '/CLUSTERING HISTOGRAM/,/^$/ {
            if ($1 ~ /^[0-9]+$/ && NF >= 5) {
                printf "   %7s | %7s | %13s | %11s | %13s\n", $1, $2, $3, $4, $5
            }
        }' "$dlg_file"
    else
        print_warning "No clustering information found in results file"
    fi
    
    # Extract binding poses summary
    echo -e "\n🧬 ${YELLOW}TOP 5 BINDING POSES:${NC}"
    echo "   Rank | Energy (kcal/mol) | Inhibition Constant"
    echo "   -----|-------------------|--------------------"
    
    # Extract top poses - Fixed extraction
    grep "DOCKED: USER    Estimated Free Energy of Binding" "$dlg_file" | head -5 | nl | while read num line; do
        # Try different extraction methods
        energy=$(echo "$line" | awk -F'=' '{print $2}' | awk '{print $1}')
        ki=$(echo "$line" | awk '{print $NF-1}')
        unit=$(echo "$line" | awk '{print $NF}')
        
        if [ -z "$energy" ]; then
            energy=$(echo "$line" | awk '{print $9}' | sed 's/=//g')
            ki=$(echo "$line" | awk '{print $12}')
            unit=$(echo "$line" | awk '{print $13}')
        fi
        
        printf "   %4s | %17s | %10s %s\n" "$num" "$energy" "$ki" "$unit"
    done
    
    # Extract run statistics
    echo -e "\n📈 ${YELLOW}DOCKING STATISTICS:${NC}"
    
    # Total runs
    total_runs=$(grep -c "DOCKED: USER    Run:" "$dlg_file")
    if [ $total_runs -gt 0 ]; then
        echo "   • Total successful runs: $total_runs"
    fi
    
    # Energy range - Fixed extraction
    all_energies=$(grep "DOCKED: USER    Estimated Free Energy of Binding" "$dlg_file" | awk -F'=' '{print $2}' | awk '{print $1}')
    if [ -z "$all_energies" ]; then
        all_energies=$(grep "DOCKED: USER    Estimated Free Energy of Binding" "$dlg_file" | awk '{print $9}' | sed 's/=//g')
    fi
    
    if [ ! -z "$all_energies" ]; then
        min_energy=$(echo "$all_energies" | sort -n | head -1)
        max_energy=$(echo "$all_energies" | sort -n | tail -1)
        echo "   • Energy range: $min_energy to $max_energy kcal/mol"
        
        # Count poses better than -7 kcal/mol (common threshold)
        good_poses=$(echo "$all_energies" | awk '$1 <= -7' | wc -l)
        echo "   • Poses with energy ≤ -7.0 kcal/mol: $good_poses"
    fi
    
    echo ""
}

# Function to create summary report
create_summary_report() {
    local results_dir=$1
    local summary_file="$results_dir/SUMMARY_REPORT.txt"
    
    print_status "Creating summary report..."
    
    # Ensure the directory exists
    mkdir -p "$results_dir"
    
    echo "AUTODOCK DOCKING RESULTS SUMMARY" > "$summary_file"
    echo "Generated on: $(date)" >> "$summary_file"
    echo "=========================================" >> "$summary_file"
    echo "" >> "$summary_file"
    
    # Table header
    printf "%-20s | %-15s | %-10s | %-15s\n" "Ligand Name" "Best Energy" "Clusters" "Status" >> "$summary_file"
    echo "----------------------------------------------------------------------" >> "$summary_file"
    
    # Process each result file
    for dlg_file in "$results_dir"/*.dlg; do
        if [ -f "$dlg_file" ]; then
            ligand_name=$(basename "$dlg_file" .dlg)
            
            # Extract best energy - Fixed extraction
            best_energy=$(grep "DOCKED: USER    Estimated Free Energy of Binding" "$dlg_file" | head -1 | awk -F'=' '{print $2}' | awk '{print $1}')
            if [ -z "$best_energy" ]; then
                best_energy=$(grep "DOCKED: USER    Estimated Free Energy of Binding" "$dlg_file" | head -1 | awk '{print $9}' | sed 's/=//g')
            fi
            [ -z "$best_energy" ] && best_energy="N/A"
            
            # Count clusters
            num_clusters=$(awk '/CLUSTERING HISTOGRAM/,/^$/ { if ($1 ~ /^[0-9]+$/ && NF >= 5) count++ } END { print count+0 }' "$dlg_file")
            
            # Determine status
            if [ "$best_energy" != "N/A" ] && [ "$best_energy" != "" ]; then
                if (( $(echo "$best_energy < -6" | bc -l 2>/dev/null || echo "0") )); then
                    status="GOOD"
                else
                    status="MODERATE"
                fi
            else
                status="FAILED"
            fi
            
            printf "%-20s | %-15s | %-10s | %-15s\n" "$ligand_name" "$best_energy" "$num_clusters" "$status" >> "$summary_file"
        fi
    done
    
    echo "" >> "$summary_file"
    echo "Legend:" >> "$summary_file"
    echo "GOOD     - Binding energy < -6.0 kcal/mol" >> "$summary_file"
    echo "MODERATE - Binding energy ≥ -6.0 kcal/mol" >> "$summary_file"
    echo "FAILED   - No valid docking results" >> "$summary_file"
    
    print_success "Summary report created: $summary_file"
}

# Function to dock a single ligand
dock_ligand() {
    local ligand_file=$1
    local ligand_name=$(basename "$ligand_file" .pdbqt)
    local job_id=$2
    
    echo -e "\n${CYAN}[$job_id] Processing: $ligand_name${NC}"
    
    # Get current working directory
    local original_dir=$(pwd)
    
    # Ensure results directory exists in the original directory
    mkdir -p "$original_dir/docking_results"
    
    # Create temporary working directory for this job
    local work_dir="tmp_dock_$$_$job_id"
    mkdir -p "$work_dir"
    
    # Copy necessary files
    cp "$ligand_file" "$work_dir/l.pdbqt"
    cp r.gpf "$work_dir/" 2>/dev/null || { print_error "[$job_id] r.gpf not found"; return 1; }
    cp r.dpf "$work_dir/" 2>/dev/null || { print_error "[$job_id] r.dpf not found"; return 1; }
    cp r.pdbqt "$work_dir/" 2>/dev/null || true
    
    cd "$work_dir"
    
    # Clean up previous results
    rm -f r.dlg r.glg 2>/dev/null
    
    # Generate grid maps (skip if keeping maps and they exist)
    if [ "$KEEP_MAPS" = true ] && [ -f "../r.A.map" ]; then
        print_status "[$job_id] Using existing grid maps..."
        cp ../r.*.map . 2>/dev/null
    else
        print_status "[$job_id] Running AutoGrid..."
        if ! autogrid4 -p r.gpf -l r.glg > autogrid.log 2>&1; then
            print_error "[$job_id] AutoGrid failed for $ligand_name"
            cd "$original_dir"
            rm -rf "$work_dir"
            return 1
        fi
        
        # Copy maps back if keeping them
        if [ "$KEEP_MAPS" = true ]; then
            cp r.*.map "$original_dir/" 2>/dev/null
        fi
    fi
    
    print_status "[$job_id] Running AutoDock..."
    # Run docking
    if ! autodock4 -p r.dpf -l r.dlg > autodock.log 2>&1; then
        print_error "[$job_id] AutoDock failed for $ligand_name"
        cd "$original_dir"
        rm -rf "$work_dir"
        return 1
    fi
    
    # Check if results were generated
    if [ -f "r.dlg" ]; then
        cp r.dlg "$original_dir/docking_results/${ligand_name}.dlg"
        print_success "[$job_id] Successfully docked $ligand_name"
        
        # Quick energy extraction - Fixed
        best_energy=$(grep "DOCKED: USER    Estimated Free Energy of Binding" r.dlg | head -1 | awk -F'=' '{print $2}' | awk '{print $1}')
        if [ -z "$best_energy" ]; then
            best_energy=$(grep "DOCKED: USER    Estimated Free Energy of Binding" r.dlg | head -1 | awk '{print $9}' | sed 's/=//g')
        fi
        
        if [ ! -z "$best_energy" ] && [ "$best_energy" != "" ]; then
            echo -e "    🎯 ${GREEN}Best binding energy: $best_energy kcal/mol${NC}"
        else
            print_warning "[$job_id] Could not extract binding energy for $ligand_name"
        fi
    else
        print_error "[$job_id] No results file generated for $ligand_name"
        cd "$original_dir"
        rm -rf "$work_dir"
        return 1
    fi
    
    cd "$original_dir"
    rm -rf "$work_dir"
    return 0
}

# Main script starts here
clear
print_header "╔══════════════════════════════════════════════════════════╗"
print_header "║              🧬 ENHANCED AUTODOCK AUTOMATION 🧬           ║"
print_header "║                  with Analysis & Reporting               ║"
print_header "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check if positioned ligands directory exists
if [ ! -d "prepared_ligands/positioned" ]; then
    print_error "prepared_ligands/positioned directory not found!"
    print_status "Run the ligand preparation script first."
    exit 1
fi

# Check if required AutoDock files exist
if [ ! -f "r.gpf" ] || [ ! -f "r.dpf" ]; then
    print_error "r.gpf or r.dpf files not found!"
    print_status "Make sure your AutoDock parameter files are in the current directory."
    exit 1
fi

# Create results directory
mkdir -p docking_results

# Count ligands
total=$(ls prepared_ligands/positioned/*.pdbqt 2>/dev/null | wc -l)

if [ $total -eq 0 ]; then
    print_error "No PDBQT files found in prepared_ligands/positioned/"
    exit 1
fi

print_status "Found $total ligands to dock"
print_status "Using $PARALLEL_JOBS parallel job(s)"
if [ "$KEEP_MAPS" = true ]; then
    print_status "Grid maps will be reused for faster processing"
fi
echo ""

# Record start time
start_time=$(date +%s)

# Run docking jobs
if [ $PARALLEL_JOBS -eq 1 ]; then
    # Sequential processing
    count=0
    for ligand_file in prepared_ligands/positioned/*.pdbqt; do
        ((count++))
        dock_ligand "$ligand_file" "$count/$total"
    done
else
    # Parallel processing
    print_status "Starting $PARALLEL_JOBS parallel docking jobs..."
    
    count=0
    for ligand_file in prepared_ligands/positioned/*.pdbqt; do
        ((count++))
        dock_ligand "$ligand_file" "$count" &
        
        # Limit number of parallel jobs
        if (( count % PARALLEL_JOBS == 0 )); then
            wait # Wait for current batch to finish
        fi
    done
    wait # Wait for remaining jobs
fi

# Calculate total time
end_time=$(date +%s)
total_time=$((end_time - start_time))
hours=$((total_time / 3600))
minutes=$(((total_time % 3600) / 60))
seconds=$((total_time % 60))

print_header "\n╔══════════════════════════════════════════════════════════╗"
print_header "║                    🎉 DOCKING COMPLETE! 🎉                ║"
print_header "╚══════════════════════════════════════════════════════════╝"

print_success "Total processing time: ${hours}h ${minutes}m ${seconds}s"
print_success "Results saved in: docking_results/"

# Create summary report
create_summary_report "docking_results"

# Detailed analysis for each ligand
if [ "$SKIP_ANALYSIS" = false ]; then
    print_header "\n📊 DETAILED ANALYSIS FOR EACH LIGAND"
    print_header "======================================"
    
    for dlg_file in docking_results/*.dlg; do
        if [ -f "$dlg_file" ]; then
            ligand_name=$(basename "$dlg_file" .dlg)
            analyze_docking_results "$dlg_file" "$ligand_name"
        fi
    done
fi

# Clean up
if [ "$KEEP_MAPS" = false ]; then
    rm -f r.*.map r.e.map r.d.map 2>/dev/null
fi

print_header "\n📁 RESULTS LOCATION:"
echo "  📋 Main results: docking_results/*.dlg"
echo "  📄 Summary report: docking_results/SUMMARY_REPORT.txt"

print_header "\n🔍 QUICK COMMANDS FOR ANALYSIS:"
echo -e "View summary report:     ${CYAN}cat docking_results/SUMMARY_REPORT.txt${NC}"
echo -e "Find best energies:      ${CYAN}grep -h 'Best Binding Energy' docking_results/*.dlg | sort -k4 -n${NC}"
echo -e "Count successful docks:  ${CYAN}ls docking_results/*.dlg | wc -l${NC}"

print_header "\n✨ Analysis complete! Check the summary report for an overview of all results."