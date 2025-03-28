package com.example.demo.entities;

import jakarta.persistence.*;
import lombok.Data;
import org.springframework.lang.NonNull;

@Entity
@Data
@Table(name = "books")
public class Book {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String title;

    private String author;

}