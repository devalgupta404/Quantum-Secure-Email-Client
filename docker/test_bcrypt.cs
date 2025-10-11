using System;
using BCrypt.Net;

class Program
{
    static void Main()
    {
        string password = "admin123";
        string hash = "$2a$11$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy";
        
        Console.WriteLine($"Testing password: {password}");
        Console.WriteLine($"Testing hash: {hash}");
        
        bool isValid = BCrypt.Net.BCrypt.Verify(password, hash);
        Console.WriteLine($"BCrypt verification result: {isValid}");
        
        // Generate a new hash for comparison
        string newHash = BCrypt.Net.BCrypt.HashPassword(password, 11);
        Console.WriteLine($"New hash: {newHash}");
        
        bool newIsValid = BCrypt.Net.BCrypt.Verify(password, newHash);
        Console.WriteLine($"New hash verification result: {newIsValid}");
    }
}
