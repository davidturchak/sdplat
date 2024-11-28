#!/usr/bin/env python3
import os
import re
import argparse
import csv
import subprocess

def find_matching_files(folder):
    pattern = re.compile(r".*_cnode([0-9][2-9]|[1-9][0-9])\.csv$")
    try:
        files = os.listdir(folder)
        return [f for f in files if pattern.match(f)]
    except Exception as e:
        print(f"Error: {e}")
        return []

def create_dat_file(csv_file, folder):
    dat_file = os.path.splitext(csv_file)[0] + ".dat"
    csv_path = os.path.join(folder, csv_file)
    dat_path = os.path.join(folder, dat_file)

    try:
        with open(csv_path, "r") as csvfile, open(dat_path, "w") as datfile:
            reader = csv.reader(csvfile)
            for row in reader:
                if len(row) >= 4:
                    datfile.write(f"{row[2]} {row[3]}\n")
        print(f"Created {dat_file}")
        return dat_file
    except Exception as e:
        print(f"Error processing {csv_file}: {e}")
        return None

def create_gnuplot_file(dat_file, folder):
    gp_file = os.path.splitext(dat_file)[0] + ".gp"
    csv_file = os.path.splitext(dat_file)[0] + ".csv"
    dat_path = os.path.join(folder, dat_file)
    gp_path = os.path.join(folder, gp_file)
    jpg_file = os.path.splitext(dat_file)[0] + ".jpg"
    jpg_path = os.path.join(folder, jpg_file)
    
    try:
        with open(gp_path, "w") as gpfile:
            gpfile.write(f"""set terminal jpeg size 800,600 enhanced font "Arial,10"
set output '{jpg_path}'

set title "Latency per Destination IP for '{dat_file}'"
set xlabel "Destination IP"
set ylabel "Latency (us)"
set xtics rotate by -45
set grid

# Treat x-values as categories (Destination IPs)
set style data histogram
set style fill solid border -1
set boxwidth 0.8

# Define colors
set style line 1 lc rgb "blue" # Normal bars
set style line 2 lc rgb "red"  # Bars with latency > 35

# Plot with conditional coloring
plot '{dat_path}' using 2:(($2 > 35) ? 2 : 1):xtic(1) title "Latency" lc variable
""")
        print(f"Created {gp_file}")
    except Exception as e:
        print(f"Error creating gnuplot file for {dat_file}: {e}")

def run_gnuplot(gp_file, folder):
    try:
        os.system(f"gnuplot {os.path.join(folder, gp_file)}")
        print(f"Generated image for {gp_file}")
    except Exception as e:
        print(f"Error running gnuplot for {gp_file}: {e}")

def cleanup_files(dat_file, gp_file, folder):
    try:
        os.remove(os.path.join(folder, dat_file))
        os.remove(os.path.join(folder, gp_file))
        print(f"Deleted temporary files: {dat_file}, {gp_file}")
    except Exception as e:
        print(f"Error deleting files: {e}")

import os
import subprocess

def merge_images(folder):
    # Collect all .jpg files in the provided folder
    jpg_files = [f for f in os.listdir(folder) if f.endswith('.jpg')]
    
    if not jpg_files:
        print("No .jpg files to merge.")
        return

    # Create a list of full paths for the .jpg files
    jpg_paths = [os.path.join(folder, jpg_file) for jpg_file in jpg_files]

    # Define the output merged image filename
    merged_image = os.path.join(folder, "Merged_output.jpg")
    
    # Use ImageMagick's montage command to merge images into 2 columns
    try:
        # Run the montage command with 2 columns and no spacing between images
        subprocess.run(["montage"] + jpg_paths + ["-tile", "2x", "-geometry", "+0+0", merged_image], check=True)
        print(f"Merged image created: {merged_image}")
    except subprocess.CalledProcessError as e:
        print(f"Error merging images: {e}")

def process_files(folder):
    matching_files = find_matching_files(folder)
    if matching_files:
        print("Processing files:")
        for csv_file in matching_files:
            print(f" - {csv_file}")
            dat_file = create_dat_file(csv_file, folder)
            if dat_file:
                create_gnuplot_file(dat_file, folder)
                gp_file = os.path.splitext(dat_file)[0] + ".gp"
                run_gnuplot(gp_file, folder)
                cleanup_files(dat_file, gp_file, folder)  # Cleanup temporary files

        # After processing all files, merge the .jpg files into a single image
        merge_images(folder)
    else:
        print("No matching files found.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Create .dat, .gp, .jpg files, merge images, and cleanup temporary files from *_cnode[02-99].csv")
    parser.add_argument("--folder", required=True, help="Path to the folder to process")
    args = parser.parse_args()

    process_files(args.folder)
