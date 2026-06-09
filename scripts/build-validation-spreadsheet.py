#!/usr/bin/env python3

import os
import sys
import re
import csv
from csv2md.table import Table


class package:
    name = "unknown name"
    passed_tier_1 = "🟥"
    passed_tier_2 = "🟥"
    passed_tier_3 = "🟥"
    passed_tier_4 = "🟥"

    def __init__(
        self, name, passed_tier_1, passed_tier_2, passed_tier_3, passed_tier_4
    ):
        self.name = name
        self.passed_tier_1 = passed_tier_1
        self.passed_tier_2 = passed_tier_2
        self.passed_tier_3 = passed_tier_3
        self.passed_tier_4 = passed_tier_4


def passed_tier(results_directory, package_name, tier):
    with open(results_directory + "/" + package_name, "r") as results_file:
        for line in results_file:
            if "passed tier " + str(tier) in line:
                return True
    return False


def parse_results(results_directory):
    packages = []
    for package_name in os.listdir(results_directory):
        if package_name.endswith(".log"):
            continue

        passed_tier_1 = "🟥"
        passed_tier_2 = "🟥"
        passed_tier_3 = "🟥"
        passed_tier_4 = "🟥"

        if passed_tier(results_directory, package_name, 1):
            passed_tier_1 = "🟩"

        if passed_tier(results_directory, package_name, 2):
            # if tier 2 was passed on the first try, this run assumes that the same package
            # would have also passed tier 1 and skips testing that, which is not entirely accurate
            passed_tier_1 = "🟩"
            passed_tier_2 = "🟩"

        if passed_tier(results_directory, package_name, 3):
            # if tier 3 was passed on the first try, this run assumes that the same package
            # would have also passed tiers 1 and 2 and skips testing those, which is not entirely accurate
            passed_tier_1 = "🟩"
            passed_tier_2 = "🟩"
            passed_tier_3 = "🟩"

        if passed_tier(results_directory, package_name, 4):
            passed_tier_4 = "🟩"

        if (
            passed_tier_1 == "🟩"
            and passed_tier_2 == "🟩"
            and passed_tier_3 == "🟩"
            and passed_tier_4 == "🟩"
        ):
            # do not append package to the list if it passed all tiers
            continue

        packages.append(
            package(
                package_name, passed_tier_1, passed_tier_2, passed_tier_3, passed_tier_4
            )
        )

    # sort alphabetically by package name
    packages.sort(key=lambda package: package.name)
    return packages


def generate_csv(packages, csv_filename):
    name_header = "**Package**"
    tier_1_header = "**With `-I`**"
    tier_2_header = "**No `-I`**"
    tier_3_header = "**Building all**"
    tier_4_header = "**Repeat building all**"
    comment_header = "**Comment**"
    with open(csv_filename, "w", newline="") as csv_file:
        csv_writer = csv.writer(csv_file)
        csv_fields = [
            name_header,
            tier_1_header,
            tier_2_header,
            tier_3_header,
            tier_4_header,
            comment_header,
        ]
        csv_writer.writerow(csv_fields)

        packages_failed_at_tier_1 = 0
        packages_failed_at_tier_2 = 0
        packages_failed_at_tier_3 = 0
        packages_failed_at_tier_4 = 0

        for package in packages:

            package_row = [
                "`" + package.name + "`",
                package.passed_tier_1,
                package.passed_tier_2,
                package.passed_tier_3,
                package.passed_tier_4,
                "",
            ]
            csv_writer.writerow(package_row)

            if package.passed_tier_1 == "🟥":
                packages_failed_at_tier_1 += 1
                continue

            if package.passed_tier_2 == "🟥":
                packages_failed_at_tier_2 += 1
                continue

            if package.passed_tier_3 == "🟥":
                packages_failed_at_tier_3 += 1
                continue

            packages_failed_at_tier_4 += 1

        totals_row = [
            "**Totals**",
            packages_failed_at_tier_1,
            packages_failed_at_tier_2,
            packages_failed_at_tier_3,
            packages_failed_at_tier_4,
            "Only the lowest tier failed by each package is summed.",
        ]
        csv_writer.writerow(totals_row)


def generate_md(csv_filename):
    with open(csv_filename) as csv_file:
        md_table = Table.parse_csv(csv_file)

    print(md_table.markdown())


def main():
    if len(sys.argv) != 3:
        print(
            "usage: "
            + sys.argv[0]
            + " [build validation results directory] [output csv filename]"
        )
        exit(1)

    results_directory = sys.argv[1]
    csv_filename = sys.argv[2]

    # get sorted list of packages that failed at least 1 tier
    packages = parse_results(results_directory)

    # save list of failed packages as csv file
    generate_csv(packages, csv_filename)

    # convert the csv to md and print to stdout
    generate_md(csv_filename)


if __name__ == "__main__":
    main()
