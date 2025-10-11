using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace QuMail.EmailProtocol.Migrations
{
    /// <inheritdoc />
    public partial class AddPqcKeyFields : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTime>(
                name: "PqcKeyGeneratedAt",
                table: "Users",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "PqcPrivateKey",
                table: "Users",
                type: "character varying(2048)",
                maxLength: 2048,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "PqcPublicKey",
                table: "Users",
                type: "character varying(2048)",
                maxLength: 2048,
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "PqcKeyGeneratedAt",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "PqcPrivateKey",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "PqcPublicKey",
                table: "Users");
        }
    }
}
